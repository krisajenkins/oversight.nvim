-- Diff view buffer controller

local Buffer = require("oversight.lib.buffer")
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

---@class DiffViewBuffer
---@field buffer Buffer Buffer instance
---@field events EventEmitter Event emitter for decoupled communication
---@field repo VcsBackend VCS backend (git or jj)
---@field session ReviewSession Review session
---@field current_file File|nil Current file being displayed
---@field file_diffs table<string, FileDiff> Cached file diffs
local DiffViewBuffer = {}
DiffViewBuffer.__index = DiffViewBuffer

---Create a new diff view buffer
---@param opts DiffViewBufferOpts Options
---@return DiffViewBuffer instance
function DiffViewBuffer.new(opts)
	local instance = setmetatable({
		repo = opts.repo,
		session = opts.session,
		current_file = nil,
		file_diffs = {},
		events = EventEmitter.new(),
	}, DiffViewBuffer)

	instance.buffer = Buffer.new({
		name = "oversight://diff",
		filetype = "oversight-diff",
		modifiable = false,
		readonly = true,
	})

	instance:_setup_mappings()

	return instance
end

---Setup keymappings for the buffer
function DiffViewBuffer:_setup_mappings()
	local buf = self.buffer

	-- Scrolling
	buf:map("n", "j", function()
		vim.cmd("normal! j")
	end, { desc = "Scroll down" })

	buf:map("n", "k", function()
		vim.cmd("normal! k")
	end, { desc = "Scroll up" })

	buf:map("n", "<C-d>", function()
		local keys = vim.api.nvim_replace_termcodes("<C-d>", true, false, true)
		vim.api.nvim_feedkeys(keys, "n", false)
	end, { desc = "Half page down" })

	buf:map("n", "<C-u>", function()
		local keys = vim.api.nvim_replace_termcodes("<C-u>", true, false, true)
		vim.api.nvim_feedkeys(keys, "n", false)
	end, { desc = "Half page up" })

	buf:map("n", "<C-f>", function()
		local keys = vim.api.nvim_replace_termcodes("<C-f>", true, false, true)
		vim.api.nvim_feedkeys(keys, "n", false)
	end, { desc = "Page down" })

	buf:map("n", "<C-b>", function()
		local keys = vim.api.nvim_replace_termcodes("<C-b>", true, false, true)
		vim.api.nvim_feedkeys(keys, "n", false)
	end, { desc = "Page up" })

	-- Hunk navigation
	buf:map("n", "[", function()
		self:jump_to_hunk(-1)
	end, { desc = "Previous hunk" })

	buf:map("n", "]", function()
		self:jump_to_hunk(1)
	end, { desc = "Next hunk" })

	-- Comment actions
	buf:map("n", "c", function()
		-- If on a comment, edit it; otherwise add a new comment
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

---Show diff for a specific file
---@param file File File info
function DiffViewBuffer:show_file(file)
	self.current_file = file

	-- Get or cache the diff
	if not self.file_diffs[file.path] then
		local diff = self.repo:get_file_diff(file.path)
		if diff then
			diff.status = file.status
			self.file_diffs[file.path] = diff
		end
	end

	self:render()
end

---Calculate column width for side-by-side view
---@return number width Column width
function DiffViewBuffer:_get_col_width()
	local win = self.buffer:get_window()
	if not win then
		return 40
	end

	local total_width = vim.api.nvim_win_get_width(win)
	-- Layout: 4 (old line#) + 1 (space) + content + 3 (separator) + 4 (new line#) + 1 (space) + content
	-- So: total = 4 + 1 + col_width + 3 + 4 + 1 + col_width = 13 + 2*col_width
	local col_width = math.floor((total_width - 13) / 2)
	return math.max(col_width, 20)
end

---Render the diff view
function DiffViewBuffer:render()
	if not self.current_file then
		local Ui = require("oversight.lib.ui")
		self.buffer:render({
			Ui.text("Select a file to view diff", { highlight = "Comment" }),
		})
		return
	end

	local diff = self.file_diffs[self.current_file.path]
	if not diff then
		local Ui = require("oversight.lib.ui")
		self.buffer:render({
			Ui.text("No diff available for " .. self.current_file.path, { highlight = "Comment" }),
		})
		return
	end

	-- Get comments for this file
	local comments = {}
	if self.session then
		comments = self.session:get_file_comments(self.current_file.path)
	end

	-- Get reviewed status
	local reviewed = self.current_file.reviewed or false

	local col_width = self:_get_col_width()
	local components = DiffViewUI.create_file_diff(diff, comments, col_width, reviewed)

	-- Add keybindings hint at the top
	table.insert(components, 1, DiffViewUI.create_keybindings_hint())

	self.buffer:render(components)
end

---Jump to next/previous hunk
---@param direction number 1 for next, -1 for previous
function DiffViewBuffer:jump_to_hunk(direction)
	local lines = self.buffer:get_lines(0, -1)
	local cursor = self.buffer:get_cursor()
	local current_line = cursor[1]

	local hunk_lines = {}
	for i, line in ipairs(lines) do
		if line:match("^@@") then
			table.insert(hunk_lines, i)
		end
	end

	if #hunk_lines == 0 then
		return
	end

	local target_line = nil
	if direction > 0 then
		-- Find next hunk
		for _, line_num in ipairs(hunk_lines) do
			if line_num > current_line then
				target_line = line_num
				break
			end
		end
		-- Wrap around
		if not target_line then
			target_line = hunk_lines[1]
		end
	else
		-- Find previous hunk
		for i = #hunk_lines, 1, -1 do
			if hunk_lines[i] < current_line then
				target_line = hunk_lines[i]
				break
			end
		end
		-- Wrap around
		if not target_line then
			target_line = hunk_lines[#hunk_lines]
		end
	end

	if target_line then
		self.buffer:set_cursor(target_line, 0)
	end
end

---Get line info at cursor
---@return LineInfo|nil info Line info or nil
function DiffViewBuffer:_get_line_at_cursor()
	local component = self.buffer:get_component_at_cursor()
	if component and component:is_interactive() then
		return component:get_item()
	end
	return nil
end

---Add a line comment
function DiffViewBuffer:add_line_comment()
	if not self.current_file then
		return
	end

	local item = self:_get_line_at_cursor()
	if not item or item.type ~= "diff_line" then
		vim.notify("Position cursor on a diff line to add a comment", vim.log.levels.WARN)
		return
	end

	-- Determine which side to comment on
	local line_no = item.line_no_new or item.line_no_old
	local side = item.line_no_new and "new" or "old"

	self.events:emit("comment", {
		file = self.current_file.path,
		line = line_no,
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

---Delete comment under cursor
function DiffViewBuffer:delete_comment()
	local item = self:_get_line_at_cursor()
	if not item or item.type ~= "comment" then
		vim.notify("Position cursor on a comment to delete it", vim.log.levels.WARN)
		return
	end

	if self.session and item.comment_id then
		self.session:delete_comment(item.comment_id)
		self.session:save()
		self:render()
		vim.notify("Comment deleted", vim.log.levels.INFO)
	end
end

---Edit comment under cursor
function DiffViewBuffer:edit_comment()
	local item = self:_get_line_at_cursor()
	if not item or item.type ~= "comment" then
		return false
	end

	if self.session and item.comment_id then
		local comment = self.session:get_comment(item.comment_id)
		if comment then
			self.events:emit("edit_comment", comment)
			return true
		end
	end
	return false
end

---Toggle reviewed status for current file
function DiffViewBuffer:toggle_reviewed()
	if not self.current_file then
		return
	end

	-- Toggle in session
	if self.session then
		local new_status = self.session:toggle_file_reviewed(self.current_file.path)
		self.session:save()

		-- Update local file state
		self.current_file.reviewed = new_status

		-- Re-render to update header
		self:render()

		-- Notify listeners (to update file list)
		self.events:emit("toggle_reviewed", self.current_file)

		local status_text = new_status and "reviewed" or "not reviewed"
		vim.notify(self.current_file.path .. " marked as " .. status_text, vim.log.levels.INFO)
	end
end

---Open the current file in editor at the line under cursor
function DiffViewBuffer:open_file()
	if not self.current_file then
		return
	end

	-- Get line number from cursor position
	local item = self:_get_line_at_cursor()
	local line_no = nil
	if item and item.type == "diff_line" then
		-- Prefer new line number (the current state of the file)
		line_no = item.line_no_new or item.line_no_old
	end

	self.events:emit("open_file", self.current_file, line_no)
end

---Jump to first content line (skipping keybindings hint)
function DiffViewBuffer:jump_to_first_content()
	-- Line 1 is the keybindings hint, line 2+ is content
	-- Find the first file header line (starts with "===")
	local lines = self.buffer:get_lines(0, 10)
	for i, line in ipairs(lines) do
		if line:match("^===") then
			self.buffer:set_cursor(i, 0)
			return
		end
	end
	-- Fallback to line 2 if no header found
	if #lines >= 2 then
		self.buffer:set_cursor(2, 0)
	end
end

---Show the buffer in the current window
function DiffViewBuffer:show()
	self.buffer:show()
	self:render()
end

---Get buffer handle
---@return number handle Buffer handle
function DiffViewBuffer:get_handle()
	return self.buffer:get_handle()
end

---Close the buffer
function DiffViewBuffer:close()
	self.events:clear()
	self.buffer:close()
end

---Refresh the diff view
function DiffViewBuffer:refresh()
	-- Clear cache and re-render
	self.file_diffs = {}
	if self.current_file then
		self:show_file(self.current_file)
	end
end

return DiffViewBuffer
