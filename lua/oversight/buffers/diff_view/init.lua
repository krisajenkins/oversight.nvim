-- Diff view buffer controller
--
-- Two scratch buffers, side by side, holding the whole file at the base
-- revision and the whole file now. Neovim's own diff does the rest: it decides
-- what moved, paints DiffAdd/DiffChange/DiffDelete, keeps the two panes aligned
-- with filler lines, and answers `[c`/`]c`. Nothing here parses a diff.
--
-- The buffers persist across files and have their contents swapped, rather than
-- a fresh pair per file: that keeps the `Buffer` class, the per-buffer keymaps
-- and the tab-level `BufEnter` installer working as they are, and `:diffthis`
-- is per *window*, so it is set once at layout time.

local Buffer = require("oversight.lib.buffer")
local Binary = require("oversight.lib.binary")
local EventEmitter = require("oversight.lib.events")
local DiffViewUI = require("oversight.buffers.diff_view.ui")

-- Events emitted by DiffViewBuffer:
---@alias DiffViewBufferEvent
---| "comment" # (context: CommentContext) - Request to add a comment
---| "edit_comment" # (comment: Comment) - Request to edit existing comment
---| "toggle_reviewed" # (file: File) - File reviewed status was toggled
---| "open_file" # (file: File, line: number|nil) - Request to open file at line
---| "quit" # () - Request to close the review

---@class DiffViewBufferOpts
---@field repo VcsBackend VCS backend (git or jj)
---@field session ReviewSession Review session

---The two sides of one file, ready to be put into the buffers.
---@class DiffSides
---@field old string[] Content at the base revision
---@field new string[] Content in the working copy
---@field diffable boolean False when there is nothing to diff (binary, error)
---@field filetype string|nil Filetype for syntax highlighting

---@class DiffViewBuffer
---@field old Buffer Base-revision buffer
---@field new Buffer Working-copy buffer
---@field old_win number|nil Window showing the base revision
---@field new_win number|nil Window showing the working copy
---@field events EventEmitter Event emitter for decoupled communication
---@field repo VcsBackend VCS backend (git or jj)
---@field session ReviewSession Review session
---@field current_file File|nil Current file being displayed
---@field diffable boolean Whether the current file is being diffed
local DiffViewBuffer = {}
DiffViewBuffer.__index = DiffViewBuffer

-- One namespace for every comment mark, on both buffers.
local COMMENT_NS = vim.api.nvim_create_namespace("oversight_comments")

---Window options that must survive `:diffthis`, which sets its own.
---
---`foldenable` is the one that matters: diff mode folds every unchanged region
---by default, and a folded comment is an invisible comment. `]c` is how you
---skip the context here.
local DIFF_WINDOW_OPTS = {
	foldenable = false,
	foldcolumn = "0",
	wrap = false,
	number = true,
	relativenumber = false,
	signcolumn = "no",
	cursorline = true,
	scrolloff = 5,
}

---Create a new diff view buffer
---@param opts DiffViewBufferOpts Options
---@return DiffViewBuffer instance
function DiffViewBuffer.new(opts)
	local instance = setmetatable({
		repo = opts.repo,
		session = opts.session,
		current_file = nil,
		diffable = false,
		-- Display row of each line, per side, for placing a comment's mirror.
		-- See _display_rows.
		rows = nil,
		-- Extmark id to comment id, per buffer handle.
		marks = {},
		events = EventEmitter.new(),
	}, DiffViewBuffer)

	instance.old = Buffer.new({
		name = "oversight://old",
		filetype = "",
		modifiable = false,
		readonly = true,
		window_opts = DIFF_WINDOW_OPTS,
	})
	instance.new = Buffer.new({
		name = "oversight://new",
		filetype = "",
		modifiable = false,
		readonly = true,
		window_opts = DIFF_WINDOW_OPTS,
	})

	instance:_setup_mappings()

	return instance
end

---Setup keymappings on both buffers
function DiffViewBuffer:_setup_mappings()
	for _, buf in ipairs({ self.old, self.new }) do
		self:_setup_buffer_mappings(buf)
	end
end

---@param buf Buffer
function DiffViewBuffer:_setup_buffer_mappings(buf)
	-- Hunk navigation
	buf:map("n", "[", function()
		self:jump_to_hunk(-1)
	end, { desc = "Previous hunk" })

	buf:map("n", "]", function()
		self:jump_to_hunk(1)
	end, { desc = "Next hunk" })

	-- Comment actions
	buf:map("n", "c", function()
		-- If the cursor is on a commented line, edit it; otherwise add a new one
		if not self:edit_comment() then
			self:add_line_comment()
		end
	end, { desc = "Add/edit comment" })

	buf:map("n", "C", function()
		self:add_file_comment()
	end, { desc = "Add file comment" })

	buf:map("n", "dd", function()
		self:delete_comment()
	end, { desc = "Delete comment" })

	-- Review actions
	buf:map("n", "r", function()
		self:toggle_reviewed()
	end, { desc = "Toggle file reviewed" })

	-- Quit
	buf:map("n", "q", function()
		self.events:emit("quit")
	end, { desc = "Quit" })

	-- Open file at current line
	buf:map("n", "<CR>", function()
		self:open_file()
	end, { desc = "Open file at line" })

	buf:map("n", "o", function()
		self:open_file()
	end, { desc = "Open file at line" })
end

-- ---------------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------------

---Put the two buffers into the two windows and turn diff mode on.
---@param old_win number Window for the base revision
---@param new_win number Window for the working copy
function DiffViewBuffer:attach(old_win, new_win)
	self.old_win = old_win
	self.new_win = new_win

	vim.api.nvim_win_set_buf(old_win, self.old:get_handle())
	vim.api.nvim_win_set_buf(new_win, self.new:get_handle())

	self:_set_diff_mode(true)
	self:render()
end

---@return number[] wins The diff windows that are still valid
function DiffViewBuffer:_wins()
	local wins = {}
	for _, win in ipairs({ self.old_win, self.new_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			table.insert(wins, win)
		end
	end
	return wins
end

---Turn Neovim's diff on or off for both windows, then put back the window
---options `:diffthis` and `:diffoff` overwrite.
---@param enabled boolean
function DiffViewBuffer:_set_diff_mode(enabled)
	for _, win in ipairs(self:_wins()) do
		vim.api.nvim_win_call(win, function()
			vim.cmd(enabled and "diffthis" or "diffoff")
			for option, value in pairs(DIFF_WINDOW_OPTS) do
				vim.api.nvim_set_option_value(option, value, { win = win })
			end
		end)
	end
	self.diffable = enabled
end

---Which side the cursor is on. Defaults to the working copy, which is what a
---caller outside either window (a test, a callback) means by "the file".
---@return "old"|"new" side
function DiffViewBuffer:_current_side()
	return vim.api.nvim_get_current_win() == self.old_win and "old" or "new"
end

---@param side "old"|"new"
---@return Buffer buffer
function DiffViewBuffer:_buffer(side)
	return side == "old" and self.old or self.new
end

---@param side "old"|"new"
---@return number|nil win
function DiffViewBuffer:_window(side)
	return side == "old" and self.old_win or self.new_win
end

-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------

---Read both sides of a file.
---@param file File
---@return DiffSides sides
function DiffViewBuffer:_read_sides(file)
	-- A rename's content lived under its old name at the base revision.
	local base_path = file.old_path or file.path

	local base = {}
	if file.status ~= "A" then
		base = self.repo:get_file_at_base(base_path)
		if not base then
			return {
				old = DiffViewUI.notice("Could not read " .. base_path .. " at the base revision"),
				new = {},
				diffable = false,
			}
		end
	end

	local working = {}
	if file.status ~= "D" then
		working = self.repo:read_file(file.path) or {}
	end

	-- The working copy is sniffed on disk because readfile cannot report a NUL;
	-- the base arrived down a pipe, so its lines can be checked directly.
	local binary = Binary.lines_are_binary(base)
		or (file.status ~= "D" and Binary.file_is_binary(self.repo:get_root() .. "/" .. file.path))

	if binary then
		return {
			old = {},
			new = DiffViewUI.notice("Binary file: " .. file.path, "(no diff to display)"),
			diffable = false,
		}
	end

	return {
		old = base,
		new = working,
		diffable = true,
		filetype = vim.filetype.match({ filename = file.path }),
	}
end

---Replace a buffer's contents, briefly lifting the readonly flags.
---@param buffer Buffer
---@param lines string[]
---@param filetype string|nil
local function set_content(buffer, lines, filetype)
	local handle = buffer:get_handle()

	vim.api.nvim_set_option_value("readonly", false, { buf = handle })
	vim.api.nvim_set_option_value("modifiable", true, { buf = handle })
	vim.api.nvim_buf_set_lines(handle, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = handle })
	vim.api.nvim_set_option_value("readonly", true, { buf = handle })

	-- Syntax highlighting comes from the filetype alone: setting it runs the
	-- FileType autocmds, which is how both Vim syntax and a treesitter setup
	-- attach to any other buffer. Nothing here re-implements highlighting.
	vim.api.nvim_set_option_value("filetype", filetype or "", { buf = handle })
end

---@class ShowFileOpts
---@field keep_cursor? boolean Leave the cursor where it is, for a refresh in
---place rather than a move to a different file

---Show a file's diff
---@param file File File info
---@param opts? ShowFileOpts
function DiffViewBuffer:show_file(file, opts)
	opts = opts or {}
	self.current_file = file

	local cursors = opts.keep_cursor and self:_cursors() or nil

	local sides = self:_read_sides(file)
	set_content(self.old, sides.old, sides.filetype)
	set_content(self.new, sides.new, sides.filetype)

	self:_set_diff_mode(sides.diffable)
	if sides.diffable then
		for _, win in ipairs(self:_wins()) do
			vim.api.nvim_win_call(win, function()
				vim.cmd("diffupdate")
			end)
		end
	end

	self.rows = nil
	self:render()

	if cursors then
		self:_restore_cursors(cursors)
	else
		self:jump_to_first_hunk()
	end
	self:_align_base_cursor()
end

---Put the base side's cursor beside the working side's.
---
---`cursorbind` only syncs the window you are moving in, and we move the
---working-copy window's cursor while the file list still has focus. Without
---this, the base pane keeps whatever line the previous file left it on.
function DiffViewBuffer:_align_base_cursor()
	local win = self.old_win
	if not win or not vim.api.nvim_win_is_valid(win) or not self.new_win then
		return
	end

	local line = self:_counterpart("new", vim.api.nvim_win_get_cursor(self.new_win)[1])
	if line then
		pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
	end
end

---@return table<string, number> cursors Cursor line per side
function DiffViewBuffer:_cursors()
	local cursors = {}
	for _, side in ipairs({ "old", "new" }) do
		local win = self:_window(side)
		if win and vim.api.nvim_win_is_valid(win) then
			cursors[side] = vim.api.nvim_win_get_cursor(win)[1]
		end
	end
	return cursors
end

---@param cursors table<string, number>
function DiffViewBuffer:_restore_cursors(cursors)
	for side, line in pairs(cursors) do
		local win = self:_window(side)
		local buffer = self:_buffer(side)
		if win and vim.api.nvim_win_is_valid(win) then
			local last = math.max(1, vim.api.nvim_buf_line_count(buffer:get_handle()))
			pcall(vim.api.nvim_win_set_cursor, win, { math.min(line, last), 0 })
		end
	end
end

---Redraw everything that is not the diff itself: the winbars and the comments.
function DiffViewBuffer:render()
	self:_render_winbars()
	self:_render_comments()
end

function DiffViewBuffer:_render_winbars()
	local file = self.current_file
	if not file then
		self:_set_winbar(self.old_win, "")
		self:_set_winbar(self.new_win, " " .. "%#OversightSeparator#Select a file%*")
		return
	end

	self:_set_winbar(self.old_win, DiffViewUI.base_winbar(file.old_path or file.path))
	self:_set_winbar(self.new_win, DiffViewUI.working_winbar(file.path, file.status, file.reviewed or false))
end

---@param win number|nil
---@param text string
function DiffViewBuffer:_set_winbar(win, text)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_option_value("winbar", text, { win = win })
	end
end

-- ---------------------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------------------

---The display row each line occupies, per side.
---
---Neovim aligns the two panes by inserting filler rows, so a line's position on
---screen is its number plus every filler above it. Two lines that share a
---display row are counterparts — which is all the mirroring needs to know, and
---it needs no diff parsing to find out.
---@return table<string, number[]> rows
function DiffViewBuffer:_display_rows()
	if self.rows then
		return self.rows
	end

	local rows = { old = {}, new = {} }
	for _, side in ipairs({ "old", "new" }) do
		local win = self:_window(side)
		if win and vim.api.nvim_win_is_valid(win) then
			rows[side] = vim.api.nvim_win_call(win, function()
				local out, fillers = {}, 0
				for line = 1, vim.api.nvim_buf_line_count(0) do
					fillers = fillers + vim.fn.diff_filler(line)
					out[line] = line + fillers
				end
				return out
			end)
		end
	end

	self.rows = rows
	return rows
end

---The line on the other side that sits at the same display row.
---
---When there is no such line — the anchor is an added or deleted line, whose
---counterpart is filler rather than text — the nearest line above it takes the
---mirror instead. Both sides still gain the same number of rows, so they are
---back in step below the comment; only the few filler rows between the two
---insertion points are pushed out, and those are inside the hunk being
---commented on.
---@param side "old"|"new" The side the comment is on
---@param line number 1-indexed line on that side
---@return number|nil counterpart 1-indexed line on the other side
function DiffViewBuffer:_counterpart(side, line)
	local rows = self:_display_rows()
	local target = rows[side][line]
	if not target then
		return nil
	end

	local other = rows[side == "old" and "new" or "old"]
	local nearest = nil
	for candidate, row in ipairs(other) do
		if row == target then
			return candidate
		end
		if row > target then
			break
		end
		nearest = candidate
	end
	return nearest
end

function DiffViewBuffer:_render_comments()
	self.marks = {}
	for _, side in ipairs({ "old", "new" }) do
		vim.api.nvim_buf_clear_namespace(self:_buffer(side):get_handle(), COMMENT_NS, 0, -1)
	end

	if not self.current_file or not self.session then
		return
	end

	local comments = self.session:get_file_comments(self.current_file.path)
	if #comments == 0 then
		return
	end

	for _, comment in ipairs(comments) do
		self:_place_comment(comment)
	end
end

---@param comment Comment
function DiffViewBuffer:_place_comment(comment)
	local lines = DiffViewUI.comment_virt_lines(comment)

	---@type "old"|"new"
	local side = "new"
	local anchor
	if comment.line then
		side = comment.side == "old" and "old" or "new"
		anchor = self:_clamp(side, comment.line)
	else
		-- A file-level comment hangs off the last line of the working copy, which
		-- is where the old renderer put it too. Above the first line would read
		-- better, but `virt_lines_above` on line 1 has nowhere to draw — there is
		-- no screen row above the top of the window — and Neovim omits it in
		-- silence rather than complaining.
		anchor = vim.api.nvim_buf_line_count(self:_buffer(side):get_handle())
	end

	self:_mark(side, anchor, lines, comment.id)

	local mirror = self:_counterpart(side, anchor)
	if mirror then
		self:_mark(side == "old" and "new" or "old", mirror, DiffViewUI.blank_virt_lines(#lines), nil)
	end
end

---Keep an anchor inside the buffer. A comment can outlive the lines it was
---written against — the session drops comments when a file's diff moves, but
---not when the file merely shrinks between one refresh and the next.
---@param side "old"|"new"
---@param line number
---@return number line
function DiffViewBuffer:_clamp(side, line)
	local count = math.max(1, vim.api.nvim_buf_line_count(self:_buffer(side):get_handle()))
	return math.max(1, math.min(line, count))
end

---@param side "old"|"new"
---@param line number 1-indexed anchor line
---@param virt_lines table[]
---@param comment_id string|nil The comment this mark carries, if any
function DiffViewBuffer:_mark(side, line, virt_lines, comment_id)
	local handle = self:_buffer(side):get_handle()
	local ok, id = pcall(vim.api.nvim_buf_set_extmark, handle, COMMENT_NS, line - 1, 0, {
		virt_lines = virt_lines,
	})
	if ok and comment_id then
		self.marks[handle] = self.marks[handle] or {}
		self.marks[handle][id] = comment_id
	end
end

---The comment attached to the line under the cursor, if there is one.
---
---There is no cursor position "on" a comment any more: virtual lines are not
---buffer lines. The line a comment hangs off is what identifies it.
---@return Comment|nil comment
function DiffViewBuffer:_comment_at_cursor()
	if not self.session then
		return nil
	end

	local side = self:_current_side()
	local win = self:_window(side)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return nil
	end

	local handle = self:_buffer(side):get_handle()
	local row = vim.api.nvim_win_get_cursor(win)[1] - 1
	local by_id = self.marks[handle] or {}

	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(handle, COMMENT_NS, { row, 0 }, { row, -1 }, {})) do
		local comment_id = by_id[mark[1]]
		if comment_id then
			return self.session:get_comment(comment_id)
		end
	end
	return nil
end

---Add a line comment
function DiffViewBuffer:add_line_comment()
	if not self.current_file then
		return
	end

	if not self.diffable then
		vim.notify("Nothing to comment on in this file", vim.log.levels.WARN)
		return
	end

	local side = self:_current_side()
	local win = self:_window(side)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	local handle = self:_buffer(side):get_handle()
	if vim.api.nvim_buf_line_count(handle) == 1 and vim.api.nvim_buf_get_lines(handle, 0, 1, false)[1] == "" then
		vim.notify("This side of the diff is empty", vim.log.levels.WARN)
		return
	end

	self.events:emit("comment", {
		file = self.current_file.path,
		line = vim.api.nvim_win_get_cursor(win)[1],
		side = side,
	})
end

---Add a file-level comment
function DiffViewBuffer:add_file_comment()
	if not self.current_file then
		return
	end

	self.events:emit("comment", {
		file = self.current_file.path,
		line = nil,
		side = nil,
	})
end

---Delete the comment on the line under the cursor
function DiffViewBuffer:delete_comment()
	local comment = self:_comment_at_cursor()
	if not comment then
		vim.notify("No comment on this line", vim.log.levels.WARN)
		return
	end

	self.session:delete_comment(comment.id)
	self.session:save()
	self:render()
	vim.notify("Comment deleted", vim.log.levels.INFO)
end

---Edit the comment on the line under the cursor
---@return boolean edited True if there was one
function DiffViewBuffer:edit_comment()
	local comment = self:_comment_at_cursor()
	if not comment then
		return false
	end

	self.events:emit("edit_comment", comment)
	return true
end

-- ---------------------------------------------------------------------------
-- Navigation and actions
-- ---------------------------------------------------------------------------

---Jump to the next or previous hunk, wrapping around at the ends.
---
---`]c` and `[c` are Neovim's own, and they know about one-sided hunks — a run
---of deleted lines is filler on the working-copy side, with no line of its own
---to land on. Scanning for highlighted lines would walk straight past those.
---@param direction number 1 for next, -1 for previous
function DiffViewBuffer:jump_to_hunk(direction)
	if not self.diffable then
		return
	end

	local win = vim.api.nvim_get_current_win()
	if win ~= self.old_win and win ~= self.new_win then
		return
	end

	local key = direction > 0 and "]c" or "[c"
	local before = vim.api.nvim_win_get_cursor(win)[1]
	vim.cmd("silent! normal! " .. key)
	if vim.api.nvim_win_get_cursor(win)[1] ~= before then
		return
	end

	-- No movement means there is no hunk that way, so wrap.
	local last = vim.api.nvim_buf_line_count(0)
	if direction > 0 then
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
		if vim.fn.diff_hlID(1, 1) == 0 then
			vim.cmd("silent! normal! ]c")
		end
	else
		vim.api.nvim_win_set_cursor(win, { last, 0 })
		if vim.fn.diff_hlID(last, 1) == 0 then
			vim.cmd("silent! normal! [c")
		else
			-- Inside the final hunk rather than at its start: walk up to the top
			-- of it, which is where `[c` would have left us.
			local line = last
			while line > 1 and vim.fn.diff_hlID(line - 1, 1) ~= 0 do
				line = line - 1
			end
			vim.api.nvim_win_set_cursor(win, { line, 0 })
		end
	end
end

---Put the cursor on the first hunk of the working-copy side.
function DiffViewBuffer:jump_to_first_hunk()
	local win = self.new_win
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
	if not self.diffable then
		return
	end

	vim.api.nvim_win_call(win, function()
		if vim.fn.diff_hlID(1, 1) == 0 then
			vim.cmd("silent! normal! ]c")
		end
	end)
end

---Toggle reviewed status for current file
function DiffViewBuffer:toggle_reviewed()
	if not self.current_file or not self.session then
		return
	end

	local new_status = self.session:toggle_file_reviewed(self.current_file.path)
	self.session:save()
	self.current_file.reviewed = new_status

	self:_render_winbars()
	self.events:emit("toggle_reviewed", self.current_file)

	local status_text = new_status and "reviewed" or "not reviewed"
	vim.notify(self.current_file.path .. " marked as " .. status_text, vim.log.levels.INFO)
end

---Open the current file in the editor, at the line under the cursor.
---
---Always the working copy, so a cursor on the base side is translated to its
---counterpart first — there is nothing to edit at the base revision.
function DiffViewBuffer:open_file()
	if not self.current_file then
		return
	end

	---@type number|nil
	local line = nil
	local side = self:_current_side()
	local win = self:_window(side)
	if self.diffable and win and vim.api.nvim_win_is_valid(win) then
		line = vim.api.nvim_win_get_cursor(win)[1]
		if side == "old" then
			line = self:_counterpart("old", line)
		end
	end

	self.events:emit("open_file", self.current_file, line)
end

---Get the working-copy buffer handle
---@return number handle Buffer handle
function DiffViewBuffer:get_handle()
	return self.new:get_handle()
end

---Both buffer handles, base side first
---@return number[] handles
function DiffViewBuffer:get_handles()
	return { self.old:get_handle(), self.new:get_handle() }
end

---Close the buffers and leave diff mode
function DiffViewBuffer:close()
	self.events:clear()
	self:_set_diff_mode(false)
	self.old:close()
	self.new:close()
end

---Re-read both sides of the current file, keeping the cursor where it is
function DiffViewBuffer:refresh()
	if self.current_file then
		self:show_file(self.current_file, { keep_cursor = true })
	end
end

return DiffViewBuffer
