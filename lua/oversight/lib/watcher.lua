-- Filesystem watcher for the working tree.
--
-- oversight exists to review changes an agent is making right now, so a review
-- that only updates when you remember to press `R` is showing you the past.
--
-- There is no cheap filesystem answer to "did anything in this tree change".
-- A recursive `fs_event` is macOS/Windows-only and unreliable, and one poller
-- per file or per directory does not scale. So this module uses two signals
-- with different costs and different latencies, and needs both:
--
--   1. **fs_poll**, fast (150ms) but narrow — the VCS metadata path
--      (`.git/index`, `.jj/repo/op_heads/heads`, covering commits, staging and
--      jj operations) and the files that currently have changes. This is what
--      makes editing a file you are already reviewing feel immediate, and it
--      costs nothing but a stat.
--   2. **a VCS probe**, slower (2s) but complete — ask the backend for its
--      change list and compare. This is the only thing that notices a file
--      becoming interesting in the first place: a tracked file that had no
--      changes until the agent touched it is invisible to signal 1, because
--      nothing was watching it.
--
-- Dropping either one leaves a hole. Signal 1 alone misses every newly-changed
-- file; signal 2 alone makes every edit take up to two seconds to appear.

local logger = require("oversight.logger")

-- 0.9 spells the libuv binding `vim.loop`; `vim.uv` arrived in 0.10.
local uv = vim.uv or vim.loop

local M = {}

---One logical change (a save, a `git add`, a jj operation) touches several
---paths in quick succession. Collapse them into a single callback.
local DEBOUNCE_MS = 150

---How often each poller stats its path.
local POLL_INTERVAL_MS = 500

---Upper bound on per-file pollers. Each one is a stat every POLL_INTERVAL_MS,
---so an enormous change list would otherwise turn into a steady background load.
---Files past the cap are still covered by the VCS probe, just at its latency
---rather than the poller's.
local MAX_FILE_WATCHERS = 64

---How often to ask the backend what has changed. This runs a VCS command, so it
---is deliberately far slower than the stat-based pollers — about the rate a
---shell prompt would run the same query.
local PROBE_INTERVAL_MS = 2000

---@class WatcherEntry
---@field refcount number How many views are attached to this root
---@field on_change fun() Debounced callback
---@field meta_poll userdata|nil Poller on the VCS metadata path
---@field file_polls userdata[] Pollers on the files currently under review
---@field timer userdata Debounce timer
---@field fire fun() schedule_wrap'd debounce callback
---@field on_event fun() Poller callback; kicks the debounce timer
---@field probe fun(): string|nil Cheap signature of the repository's change list
---@field probe_timer userdata|nil Repeating timer driving `probe`
---@field last_signature string|nil Most recent probe result
---@field suppressed_until number uv.hrtime()-based deadline, in ms

---@type table<string, WatcherEntry>
local entries = {}

local cleanup_registered = false

---Current monotonic time in milliseconds. `uv.now()` is the loop's cached time
---and can be stale inside a callback; hrtime always advances.
---@return number ms
local function now_ms()
	return uv.hrtime() / 1e6
end

---The VCS metadata path whose modification means "the repository moved".
---@param root string Repository root
---@param vcs_type "git"|"jj" VCS type
---@return string|nil path Path to watch, or nil if it cannot be found
local function metadata_path(root, vcs_type)
	if vcs_type == "jj" then
		-- Every jj operation writes a new op head here, including the implicit
		-- working-copy snapshot that `jj status` takes when files have changed.
		local heads = root .. "/.jj/repo/op_heads/heads"
		if vim.fn.isdirectory(heads) == 1 then
			return heads
		end
		return nil
	end

	-- git: the index covers staging and commits. In a worktree or submodule
	-- `.git` is a file pointing elsewhere, so fall back to watching that.
	local index = root .. "/.git/index"
	if vim.fn.filereadable(index) == 1 then
		return index
	end
	if vim.fn.isdirectory(root .. "/.git") == 1 or vim.fn.filereadable(root .. "/.git") == 1 then
		return root .. "/.git"
	end
	return nil
end

---Start an fs_poll on a path.
---
---`fs_poll`, not `fs_event`, and not by accident: kqueue and FSEvents stop
---delivering once the watched entry is replaced rather than modified, and
---replacement is the normal case — editors save by writing a temp file and
---renaming over the target, git rewrites `.git/index` wholesale, and every jj
---operation creates a new op-head file. A watcher that silently goes deaf after
---the first change is worse than none. Polling stats the path by name, so it
---survives all of that.
---@param path string
---@param on_event fun() Called on any change; never given the event details
---@return userdata|nil poll
local function start_poll(path, on_event)
	local poll = uv.new_fs_poll()
	if not poll then
		return nil
	end

	-- The callback runs on the libuv thread, where Neovim API calls are illegal.
	-- It does nothing but kick the debounce timer, which is allowed here; the
	-- timer's own callback is what hops back to the main loop.
	--
	-- Note that the arguments are ignored entirely. There is no portable,
	-- trustworthy "what changed" in a filesystem event — a rename gives no
	-- reliable destination name — so any callback at all, error included, means
	-- the same thing: go and re-query.
	--
	-- (The functional form, uv.fs_poll_start rather than poll:start, is used for
	-- every libuv handle in this module: lua_ls's bundled luv meta has no type
	-- for a poll or timer handle, so a handle is plain userdata and each
	-- `handle:method()` is an undefined field. The functional API is declared.)
	local ok = uv.fs_poll_start(poll, path, POLL_INTERVAL_MS, function()
		on_event()
	end)

	if not ok then
		uv.close(poll)
		return nil
	end
	return poll
end

---@param poll userdata|nil
local function stop_poll(poll)
	if poll and not uv.is_closing(poll) then
		uv.fs_poll_stop(poll)
		uv.close(poll)
	end
end

---@param entry WatcherEntry
local function stop_file_polls(entry)
	for _, poll in ipairs(entry.file_polls) do
		stop_poll(poll)
	end
	entry.file_polls = {}
end

---@param timer userdata|nil
local function stop_timer(timer)
	if timer and not uv.is_closing(timer) then
		uv.timer_stop(timer)
		uv.close(timer)
	end
end

---Release every handle an entry owns. Leaving one open keeps the libuv loop
---alive, which on quit shows up as Neovim hanging instead of exiting.
---@param entry WatcherEntry
local function stop_entry(entry)
	stop_file_polls(entry)
	stop_poll(entry.meta_poll)
	stop_timer(entry.timer)
	stop_timer(entry.probe_timer)
end

---Register the one VimLeavePre hook that tears every watcher down.
local function ensure_cleanup_registered()
	if cleanup_registered then
		return
	end
	cleanup_registered = true

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("oversight_watcher", { clear = true }),
		callback = function()
			M.cleanup_all()
		end,
	})
end

---Re-baseline the probe without firing a change.
---
---Called after a refresh: the view now matches whatever the probe would return,
---so recording it here stops the next tick reporting our own work as news.
---@param root string Repository root
function M.sync_probe(root)
	local entry = entries[root]
	if not entry or not entry.probe then
		return
	end
	local ok, signature = pcall(entry.probe)
	if ok then
		entry.last_signature = signature
	end
end

---@class WatchOpts
---@field on_change fun() Called (debounced, on the main loop) when anything moves
---@field probe? fun(): string|nil A cheap signature of what the view is showing —
---for review mode, the change list. Called on the main loop every
---PROBE_INTERVAL_MS; `on_change` fires when the result differs from last time.
---Without it, a file that only *becomes* changed goes unnoticed.

---Start watching a repository, or attach to an existing watch of it.
---
---Refcounted: opening review and browse mode on the same repository shares one
---set of pollers, and the last one to detach tears them down.
---@param root string Repository root
---@param vcs_type "git"|"jj" VCS type
---@param opts WatchOpts
function M.attach(root, vcs_type, opts)
	local entry = entries[root]
	if entry then
		entry.refcount = entry.refcount + 1
		entry.on_change = opts.on_change
		if opts.probe then
			entry.probe = opts.probe
		end
		return
	end

	entry = {
		refcount = 1,
		on_change = opts.on_change,
		meta_poll = nil,
		file_polls = {},
		timer = uv.new_timer(),
		probe = opts.probe,
		probe_timer = nil,
		last_signature = nil,
		suppressed_until = 0,
		fire = function() end,
		on_event = function() end,
	}

	entry.fire = vim.schedule_wrap(function()
		-- Dropped rather than deferred: the refresh that suppressed us is itself
		-- what moved the filesystem, so there is nothing new to see.
		if now_ms() < entry.suppressed_until then
			return
		end
		if entries[root] ~= entry then
			return
		end
		entry.on_change()
	end)

	local function on_event()
		if entry.timer and not uv.is_closing(entry.timer) then
			uv.timer_stop(entry.timer)
			uv.timer_start(entry.timer, DEBOUNCE_MS, 0, entry.fire)
		end
	end

	local meta = metadata_path(root, vcs_type)
	if meta then
		entry.meta_poll = start_poll(meta, on_event)
		if not entry.meta_poll then
			logger.debug("Could not watch VCS metadata at %s", meta)
		end
	end

	entry.on_event = on_event
	entries[root] = entry

	if entry.probe then
		-- Take the baseline now rather than on the first tick. The view has just
		-- been built from the current state, so this is what it is showing; a
		-- baseline captured two seconds later would silently swallow anything
		-- that changed in between.
		M.sync_probe(root)

		entry.probe_timer = uv.new_timer()
		-- The probe runs a VCS command, so unlike the fs_poll callbacks it has
		-- to be on the main loop from the outset, not just when it reports.
		uv.timer_start(
			entry.probe_timer,
			PROBE_INTERVAL_MS,
			PROBE_INTERVAL_MS,
			vim.schedule_wrap(function()
				if entries[root] ~= entry then
					return
				end
				-- Skip entirely rather than probe-and-discard: during a refresh
				-- the backend is already being queried, and asking a jj
				-- repository anything writes to it.
				if now_ms() < entry.suppressed_until then
					return
				end

				local ok, signature = pcall(entry.probe)
				if not ok or signature == nil then
					return
				end

				-- The first result is the baseline, not a change.
				if entry.last_signature == nil then
					entry.last_signature = signature
					return
				end
				if signature ~= entry.last_signature then
					entry.last_signature = signature
					entry.on_change()
				end
			end)
		)
	end

	ensure_cleanup_registered()
end

---Replace the set of individual files being watched.
---
---Called after every refresh, because the interesting files are exactly the
---ones that currently have changes — and that set moves as the agent works.
---@param root string Repository root
---@param paths string[] Repo-relative file paths
function M.set_watched_files(root, paths)
	local entry = entries[root]
	if not entry then
		return
	end

	stop_file_polls(entry)

	local watched = 0
	for _, path in ipairs(paths) do
		if watched >= MAX_FILE_WATCHERS then
			-- Say so rather than truncating in silence: a partly-watched review
			-- that looks fully watched is a trap.
			logger.debug(
				"Watching the first %d of %d changed files; the rest need a manual refresh",
				MAX_FILE_WATCHERS,
				#paths
			)
			break
		end

		local poll = start_poll(root .. "/" .. path, entry.on_event)
		if poll then
			table.insert(entry.file_polls, poll)
			watched = watched + 1
		end
	end
end

---Ignore events for the next `ms` milliseconds.
---
---This is the guard that keeps a refresh from triggering itself. Reading the
---repository is not read-only in jj: `jj status` snapshots the working copy when
---it has changed, which writes a new op head — which the metadata poller then
---reports as a change, which would refresh again. Suppressing our own window
---breaks that loop at one iteration instead of letting it echo.
---@param root string Repository root
---@param ms? number Milliseconds to stay quiet (default 1000)
function M.suppress(root, ms)
	local entry = entries[root]
	if not entry then
		return
	end
	entry.suppressed_until = now_ms() + (ms or 1000)
end

---Run `fn` with events suppressed for its duration plus a settle window.
---
---The settle window matters as much as the call itself: the poller only notices
---a write on its next tick, so a suppression that ended the instant `fn` did
---would still see the echo.
---@param root string Repository root
---@param fn fun()
function M.while_refreshing(root, fn)
	M.suppress(root, 5000)

	local ok, err = pcall(fn)

	-- Re-armed *after* the work, so the window starts from when the writes
	-- actually stopped. Two poll intervals is enough for the change to have been
	-- seen and dropped.
	M.suppress(root, POLL_INTERVAL_MS * 2 + DEBOUNCE_MS)

	if not ok then
		error(err)
	end
end

---Detach one view from a repository's watch, tearing it down at zero.
---@param root string Repository root
function M.detach(root)
	local entry = entries[root]
	if not entry then
		return
	end

	entry.refcount = entry.refcount - 1
	if entry.refcount > 0 then
		return
	end

	stop_entry(entry)
	entries[root] = nil
end

---Tear every watcher down regardless of refcount.
function M.cleanup_all()
	for root, entry in pairs(entries) do
		stop_entry(entry)
		entries[root] = nil
	end
end

---Whether a root is currently being watched. For tests and :checkhealth.
---@param root string Repository root
---@return boolean watching
function M.is_watching(root)
	return entries[root] ~= nil
end

---How many paths are being polled for a root. For tests.
---@param root string Repository root
---@return number count
function M.watched_count(root)
	local entry = entries[root]
	if not entry then
		return 0
	end
	return #entry.file_polls + (entry.meta_poll and 1 or 0)
end

return M
