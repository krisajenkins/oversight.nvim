-- Main review buffer orchestration
-- Coordinates the file list and diff view panels

local Vcs = require("oversight.lib.vcs")
local Session = require("oversight.lib.storage.session")
local FileListBuffer = require("oversight.buffers.file_list")
local DiffViewBuffer = require("oversight.buffers.diff_view")
local CommentInput = require("oversight.buffers.comment")
local HelpOverlay = require("oversight.buffers.help")

---@class ReviewBuffer
---@field repo VcsBackend VCS backend (git or jj)
---@field session ReviewSession Review session
---@field file_list FileListBuffer File list buffer
---@field diff_view DiffViewBuffer Diff view buffer
---@field tab_page number Tab page handle
---@field file_list_win number File list window handle
---@field diff_view_win number Diff view window handle
local ReviewBuffer = {}
ReviewBuffer.__index = ReviewBuffer

-- Singleton instance per repository
local instances = {}

---Open the review interface
---@return ReviewBuffer|nil instance Review buffer or nil on error
function ReviewBuffer.open()
	local dir = vim.fn.getcwd()

	-- Get VCS backend (git or jj)
	local repo = Vcs.instance(dir)
	if not repo then
		vim.notify("Not a version-controlled directory: " .. dir, vim.log.levels.ERROR)
		return nil
	end

	-- Check if already open
	local root = repo:get_root()
	if instances[root] and instances[root]:is_valid() then
		instances[root]:focus()
		instances[root]:refresh()
		return instances[root]
	end

	-- Check for changes
	if not repo:has_changes() then
		vim.notify("No changes to review", vim.log.levels.INFO)
		return nil
	end

	-- Create new instance
	local instance = ReviewBuffer.new(repo)
	instances[root] = instance

	return instance
end

---Create a new review buffer
---@param repo VcsBackend VCS backend
---@return ReviewBuffer instance
function ReviewBuffer.new(repo)
	local instance = setmetatable({
		repo = repo,
	}, ReviewBuffer)

	-- Load or create session
	instance.session = Session.load_or_create(repo:get_root(), repo:get_head())

	-- Get changed files
	local changed_files = repo:get_changed_files()

	-- Ensure files are tracked in session (with diff hashing for change detection)
	local files = {}
	for _, file in ipairs(changed_files) do
		local diff_content = repo:get_file_diff_raw(file.path)
		instance.session:ensure_file(file.path, file.status, diff_content)
		local status = instance.session:get_file_status(file.path)
		table.insert(files, {
			path = file.path,
			status = file.status,
			reviewed = status and status.reviewed or false,
		})
	end

	-- Create layout
	instance:_create_layout(files)

	return instance
end

---Create the two-panel layout
---@param files File[] List of files
function ReviewBuffer:_create_layout(files)
	-- Create new tab
	vim.cmd("tabnew")
	self.tab_page = vim.api.nvim_get_current_tabpage()

	-- Create vertical split
	vim.cmd("vsplit")

	-- Get window handles
	local wins = vim.api.nvim_tabpage_list_wins(self.tab_page)
	self.file_list_win = wins[1]
	self.diff_view_win = wins[2]

	-- Set file list width to ~25%
	local total_width = vim.o.columns
	local file_list_width = math.max(30, math.floor(total_width * 0.25))
	vim.api.nvim_win_set_width(self.file_list_win, file_list_width)

	-- Create file list buffer
	vim.api.nvim_set_current_win(self.file_list_win)
	self.file_list = FileListBuffer.new({
		files = files,
		session = self.session,
		branch = self.repo:get_branch(),
	})
	self.file_list:show()

	-- Subscribe to file list events
	self.file_list.events:on("file_select", function(file)
		self:_on_file_select(file)
	end)
	self.file_list.events:on("open_file", function(file)
		self:_on_open_file(file)
	end)
	-- toggle_reviewed: session already saved in FileListBuffer, no action needed

	-- Create diff view buffer
	vim.api.nvim_set_current_win(self.diff_view_win)
	self.diff_view = DiffViewBuffer.new({
		repo = self.repo,
		session = self.session,
	})
	self.diff_view:show()

	-- Subscribe to diff view events
	self.diff_view.events:on("comment", function(context)
		self:_on_add_comment(context)
	end)
	self.diff_view.events:on("edit_comment", function(comment)
		self:_on_edit_comment(comment)
	end)
	self.diff_view.events:on("toggle_reviewed", function(file)
		self:_on_toggle_reviewed(file)
	end)
	self.diff_view.events:on("open_file", function(file, line)
		self:_on_open_file(file, line)
	end)
	self.diff_view.events:on("quit", function()
		self:close()
	end)

	-- Setup tab-level keymappings
	self:_setup_tab_mappings()

	-- Select first file
	if #files > 0 then
		self:_on_file_select(files[1])
	end

	-- Focus file list initially
	vim.api.nvim_set_current_win(self.file_list_win)
end

---Setup tab-level keymappings
function ReviewBuffer:_setup_tab_mappings()
	local group = vim.api.nvim_create_augroup("oversight_review_" .. self.tab_page, { clear = true })

	-- Tab switching between panels
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function()
			local buf = vim.api.nvim_get_current_buf()
			local file_list_buf = self.file_list:get_handle()
			local diff_view_buf = self.diff_view:get_handle()

			if buf == file_list_buf or buf == diff_view_buf then
				-- Set Tab to switch between panels
				vim.keymap.set("n", "<Tab>", function()
					self:_toggle_focus()
				end, { buffer = buf, desc = "Toggle panel focus" })

				-- File navigation from either panel
				vim.keymap.set("n", "{", function()
					self:_navigate_file(-1)
				end, { buffer = buf, desc = "Previous file" })

				vim.keymap.set("n", "}", function()
					self:_navigate_file(1)
				end, { buffer = buf, desc = "Next file" })

				-- Export (yank to clipboard)
				vim.keymap.set("n", "y", function()
					self:export_markdown()
				end, { buffer = buf, desc = "Yank comments to clipboard" })

				-- Clear all comments
				vim.keymap.set("n", "X", function()
					self:clear_comments()
				end, { buffer = buf, desc = "Clear all comments" })

				-- Refresh
				vim.keymap.set("n", "R", function()
					self:refresh()
				end, { buffer = buf, desc = "Refresh status" })

				-- Help
				vim.keymap.set("n", "?", function()
					self:show_help()
				end, { buffer = buf, desc = "Show help" })

				-- Quit
				vim.keymap.set("n", "q", function()
					self:close()
				end, { buffer = buf, desc = "Quit review" })
			end
		end,
	})
end

---Handle file selection
---@param file File Selected file
function ReviewBuffer:_on_file_select(file)
	self.diff_view:show_file(file)
end

---Handle opening file in editor
---@param file File File to open
---@param line number|nil Optional line number to jump to
function ReviewBuffer:_on_open_file(file, line)
	-- Get the full path
	local full_path = self.repo:get_root() .. "/" .. file.path

	-- Open in a new tab to not disrupt the review layout
	vim.cmd("tabnew " .. vim.fn.fnameescape(full_path))

	-- Jump to line if specified
	if line then
		vim.api.nvim_win_set_cursor(0, { line, 0 })
	end
end

---Handle toggling reviewed status from diff view
---@param file File File that was toggled
function ReviewBuffer:_on_toggle_reviewed(file)
	-- Update file in file list using proper encapsulation
	self.file_list:update_file_reviewed(file.path, file.reviewed)
end

---Handle adding a comment
---@param context CommentContext Comment context
function ReviewBuffer:_on_add_comment(context)
	local input = CommentInput.new({
		context = context,
	})
	input.events:on("submit", function(comment_data)
		self.session:add_comment(
			comment_data.file,
			comment_data.line,
			comment_data.side,
			comment_data.type,
			comment_data.text
		)
		self.session:save()
		self.diff_view:render()
		vim.notify("Comment added", vim.log.levels.INFO)
	end)
end

---Handle editing an existing comment
---@param comment Comment Comment to edit
function ReviewBuffer:_on_edit_comment(comment)
	local input = CommentInput.new({
		context = {
			file = comment.file,
			line = comment.line,
			side = comment.side,
		},
		existing_comment = comment,
	})
	input.events:on("submit", function(comment_data)
		self.session:update_comment(comment_data.id, comment_data.type, comment_data.text)
		self.session:save()
		self.diff_view:render()
		vim.notify("Comment updated", vim.log.levels.INFO)
	end)
end

---Toggle focus between panels
function ReviewBuffer:_toggle_focus()
	-- Validate windows still exist
	if not vim.api.nvim_win_is_valid(self.file_list_win) or not vim.api.nvim_win_is_valid(self.diff_view_win) then
		return
	end

	local current_win = vim.api.nvim_get_current_win()
	if current_win == self.file_list_win then
		vim.api.nvim_set_current_win(self.diff_view_win)
		-- Position cursor on first file header (skip keybindings hint)
		self.diff_view:jump_to_first_content()
	else
		vim.api.nvim_set_current_win(self.file_list_win)
	end
end

---Navigate to next/previous file
---@param delta number 1 for next, -1 for previous
function ReviewBuffer:_navigate_file(delta)
	self.file_list:move_cursor(delta)
end

---Export review to markdown and copy to clipboard
function ReviewBuffer:export_markdown()
	if not self.session:has_comments() then
		vim.notify("No comments to export", vim.log.levels.WARN)
		return
	end

	local Export = require("oversight.lib.export")
	local markdown = Export.to_markdown(self.session, self.repo)

	-- Copy to clipboard
	vim.fn.setreg("+", markdown)
	vim.fn.setreg("*", markdown)

	local counts = self.session:get_comment_counts()
	local total = counts.note + counts.suggestion + counts.issue + counts.praise
	vim.notify(string.format("Exported %d comments to clipboard", total), vim.log.levels.INFO)
end

---Clear all comments with confirmation
function ReviewBuffer:clear_comments()
	if not self.session:has_comments() then
		vim.notify("No comments to clear", vim.log.levels.INFO)
		return
	end

	local counts = self.session:get_comment_counts()
	local total = counts.note + counts.suggestion + counts.issue + counts.praise

	-- Confirm before clearing
	vim.ui.select({ "Yes", "No" }, {
		prompt = string.format("Clear all %d comments? ", total),
	}, function(choice)
		if choice == "Yes" then
			self.session.comments = {}
			self.session:save()
			self.diff_view:render()
			vim.notify(string.format("Cleared %d comments", total), vim.log.levels.INFO)
		end
	end)
end

---Show help overlay
function ReviewBuffer:show_help()
	HelpOverlay.show()
end

---Refresh the file list and diff view with latest git status
function ReviewBuffer:refresh()
	-- Re-fetch changed files from repository
	local changed_files = self.repo:get_changed_files()

	-- Build files list with reviewed status from session
	-- Track files that were reset due to diff changes
	local files = {}
	local reset_files = {}
	for _, file in ipairs(changed_files) do
		local diff_content = self.repo:get_file_diff_raw(file.path)
		local was_reset = self.session:ensure_file(file.path, file.status, diff_content)
		if was_reset then
			table.insert(reset_files, file.path)
		end
		local status = self.session:get_file_status(file.path)
		table.insert(files, {
			path = file.path,
			status = file.status,
			reviewed = status and status.reviewed or false,
		})
	end

	-- Update file list
	self.file_list:set_files(files)

	-- Refresh diff view for current file
	local current_file = self.file_list:get_current_file()
	if current_file then
		self.diff_view:show_file(current_file)
	end

	-- Notify user about what happened
	if #reset_files > 0 then
		vim.notify(
			string.format(
				"Refreshed. %d file(s) changed and were reset: %s",
				#reset_files,
				table.concat(reset_files, ", ")
			),
			vim.log.levels.INFO
		)
	else
		vim.notify("Refreshed", vim.log.levels.INFO)
	end
end

---Check if review is still valid
---@return boolean valid True if tab and windows are valid
function ReviewBuffer:is_valid()
	return self.tab_page and vim.api.nvim_tabpage_is_valid(self.tab_page) and self.file_list and self.diff_view
end

---Focus the review tab
function ReviewBuffer:focus()
	if self.tab_page and vim.api.nvim_tabpage_is_valid(self.tab_page) then
		vim.api.nvim_set_current_tabpage(self.tab_page)
	end
end

---Close the review interface
function ReviewBuffer:close()
	-- Save session
	if self.session then
		self.session:save()
	end

	-- Close buffers
	if self.file_list then
		self.file_list:close()
	end
	if self.diff_view then
		self.diff_view:close()
	end

	-- Remove from instances
	if self.repo then
		instances[self.repo:get_root()] = nil
	end

	-- Close tab if it's our tab
	if self.tab_page and vim.api.nvim_tabpage_is_valid(self.tab_page) then
		-- Switch away first if we're on this tab
		local current_tab = vim.api.nvim_get_current_tabpage()
		if current_tab == self.tab_page then
			vim.cmd("tabprevious")
		end
		-- Now close
		local wins = vim.api.nvim_tabpage_list_wins(self.tab_page)
		for _, win in ipairs(wins) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
	end

	vim.notify("Review closed", vim.log.levels.INFO)
end

---Close all review instances
function ReviewBuffer.close_all()
	for _, instance in pairs(instances) do
		instance:close()
	end
	instances = {}
end

return ReviewBuffer
