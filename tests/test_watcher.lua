-- Tests for the working-tree watcher.
--
-- These run in a child Neovim for the same reason the async CLI tests do:
-- observing a filesystem event means `vim.wait` with the event loop live, and a
-- non-fast `vim.wait` inside a mini.test case flushes the queue of scheduled
-- cases and silently abandons the current one. See tests/CLAUDE.md.

local child, child_set = require("tests.helpers.child")()
local expect = MiniTest.expect

local T = child_set()

T["Watcher"] = MiniTest.new_set()

---Create a throwaway directory with a fake git repo inside it.
---@return string root
local function make_root()
	local root = child.lua_get([[(function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root .. "/.git", "p")
		vim.fn.writefile({ "index" }, root .. "/.git/index")
		vim.fn.writefile({ "one" }, root .. "/watched.txt")
		return root
	end)()]])
	return root
end

---Attach a watcher that counts callbacks into `_G.changes`.
---@param root string
local function attach(root)
	child.lua(string.format(
		[[
		_G.changes = 0
		require("oversight.lib.watcher").attach(%q, "git", {
			on_change = function() _G.changes = _G.changes + 1 end,
		})
	]],
		root
	))
end

---Wait for at least one change callback, returning how many arrived.
---@param timeout_ms? number
---@return number changes
local function wait_for_change(timeout_ms)
	return child.lua_get(string.format(
		[[(function()
		vim.wait(%d, function() return _G.changes > 0 end, 50)
		return _G.changes
	end)()]],
		timeout_ms or 4000
	))
end

T["Watcher"]["reports a change to a watched file"] = function()
	local root = make_root()
	attach(root)
	child.lua(string.format([[require("oversight.lib.watcher").set_watched_files(%q, { "watched.txt" })]], root))

	child.lua(string.format([[vim.fn.writefile({ "two" }, %q .. "/watched.txt")]], root))

	expect.equality(wait_for_change() >= 1, true)
end

-- Regression guard for the polling choice. `git` writes a whole new index and
-- renames it over the old one, and editors save the same way; kqueue/FSEvents
-- stop delivering for a watched path once its inode is replaced, so an
-- fs_event-based watcher goes deaf exactly when it matters.
T["Watcher"]["survives the watched file being replaced, not modified"] = function()
	local root = make_root()
	attach(root)
	child.lua(string.format([[require("oversight.lib.watcher").set_watched_files(%q, { "watched.txt" })]], root))

	child.lua(string.format(
		[[
		local root = %q
		vim.fn.writefile({ "replacement" }, root .. "/tmp-file")
		vim.fn.rename(root .. "/tmp-file", root .. "/watched.txt")
	]],
		root
	))

	expect.equality(wait_for_change() >= 1, true)
end

T["Watcher"]["reports a change to the VCS metadata"] = function()
	local root = make_root()
	attach(root)

	-- No per-file watchers at all: the metadata poller alone must notice.
	child.lua(string.format([[vim.fn.writefile({ "index", "changed" }, %q .. "/.git/index")]], root))

	expect.equality(wait_for_change() >= 1, true)
end

T["Watcher"]["collapses a burst of writes into one callback"] = function()
	local root = make_root()
	attach(root)
	child.lua(string.format([[require("oversight.lib.watcher").set_watched_files(%q, { "watched.txt" })]], root))

	child.lua(string.format(
		[[
		local root = %q
		for i = 1, 5 do
			vim.fn.writefile({ "write " .. i }, root .. "/watched.txt")
			vim.fn.writefile({ "index " .. i }, root .. "/.git/index")
		end
	]],
		root
	))

	local changes = wait_for_change()
	expect.equality(changes >= 1, true)
	-- Ten writes across two watched paths; the debounce means far fewer
	-- callbacks than writes. Not exactly one: the poll interval can straddle
	-- the burst.
	expect.equality(changes <= 3, true)
end

-- Reading a jj repository is not read-only — `jj status` snapshots the working
-- copy, writing a new op head — so a refresh would otherwise trigger the
-- watcher, which would refresh again.
T["Watcher"]["ignores events raised during a refresh"] = function()
	local root = make_root()
	attach(root)
	child.lua(string.format([[require("oversight.lib.watcher").set_watched_files(%q, { "watched.txt" })]], root))

	child.lua(string.format(
		[[
		require("oversight.lib.watcher").while_refreshing(%q, function()
			vim.fn.writefile({ "written by the refresh" }, %q .. "/watched.txt")
		end)
	]],
		root,
		root
	))

	-- Long enough for a poll tick and the debounce to have fired if they were
	-- going to.
	local changes = child.lua_get([[(function() vim.wait(1500); return _G.changes end)()]])
	expect.equality(changes, 0)
end

T["Watcher"]["stops reporting once every view detaches"] = function()
	local root = make_root()
	attach(root)
	child.lua(string.format([[require("oversight.lib.watcher").set_watched_files(%q, { "watched.txt" })]], root))

	-- Two views on one repository share a single set of pollers.
	child.lua(
		string.format([[require("oversight.lib.watcher").attach(%q, "git", { on_change = function() end })]], root)
	)
	child.lua(string.format([[require("oversight.lib.watcher").detach(%q)]], root))
	expect.equality(child.lua_get(string.format([[require("oversight.lib.watcher").is_watching(%q)]], root)), true)

	child.lua(string.format([[require("oversight.lib.watcher").detach(%q)]], root))
	expect.equality(child.lua_get(string.format([[require("oversight.lib.watcher").is_watching(%q)]], root)), false)

	child.lua(string.format([[vim.fn.writefile({ "after detach" }, %q .. "/watched.txt")]], root))
	local changes = child.lua_get([[(function() vim.wait(1500); return _G.changes end)()]])
	expect.equality(changes, 0)
end

-- The stat pollers only watch files that already have changes, so they are
-- structurally blind to a clean file becoming dirty — which is most of what an
-- agent does. The probe is what closes that, and an end-to-end run against a
-- real repository is what found the gap in the first place.
T["Watcher"]["reports a change the pollers cannot see, via the probe"] = function()
	local root = make_root()

	child.lua(string.format(
		[[
		local root = %q
		_G.changes = 0
		_G.signature = "before"
		require("oversight.lib.watcher").attach(root, "git", {
			on_change = function() _G.changes = _G.changes + 1 end,
			probe = function() return _G.signature end,
		})
	]],
		root
	))

	-- Nothing on disk moves at all: only the backend's answer does.
	child.lua([[_G.signature = "after"]])

	expect.equality(wait_for_change() >= 1, true)
end

T["Watcher"]["does not report an unchanged probe result"] = function()
	local root = make_root()

	child.lua(string.format(
		[[
		local root = %q
		_G.changes = 0
		_G.probes = 0
		require("oversight.lib.watcher").attach(root, "git", {
			on_change = function() _G.changes = _G.changes + 1 end,
			probe = function() _G.probes = _G.probes + 1; return "steady" end,
		})
	]],
		root
	))

	local outcome = child.lua_get([[(function()
		vim.wait(5000, function() return _G.probes >= 2 end, 100)
		return { probes = _G.probes, changes = _G.changes }
	end)()]])

	-- Probed repeatedly, reported never: the first result is the baseline and
	-- the rest match it.
	expect.equality(outcome.probes >= 2, true)
	expect.equality(outcome.changes, 0)
end

T["Watcher"]["caps the number of per-file pollers"] = function()
	local root = make_root()
	attach(root)

	local watched = child.lua_get(string.format(
		[[(function()
		local root = %q
		local paths = {}
		for i = 1, 200 do
			local name = "file" .. i .. ".txt"
			vim.fn.writefile({ "x" }, root .. "/" .. name)
			table.insert(paths, name)
		end
		local Watcher = require("oversight.lib.watcher")
		Watcher.set_watched_files(root, paths)
		return Watcher.watched_count(root)
	end)()]],
		root
	))

	-- 64 files plus the one metadata poller.
	expect.equality(watched, 65)
end

return T
