-- Browse mode buffer orchestration
-- Coordinates the file tree and file view panels for codebase browsing

local Vcs = require("oversight.lib.vcs")
local Session = require("oversight.lib.session")
local FileTreeBuffer = require("oversight.buffers.file_tree")
local FileViewBuffer = require("oversight.buffers.file_view")
local CommentInput = require("oversight.buffers.comment")
local HelpOverlay = require("oversight.buffers.help")

---@class BrowseBuffer
---@field repo VcsBackend VCS backend (git or jj)
---@field session ReviewSession Review session
---@field file_tree FileTreeBuffer File tree buffer
---@field file_view FileViewBuffer File view buffer
---@field tab_page number Tab page handle
---@field file_tree_win number File tree window handle
---@field file_view_win number File view window handle
local BrowseBuffer = {}
BrowseBuffer.__index = BrowseBuffer

-- Singleton instance per repository
local instances = {}

---Open the browse interface
---@return BrowseBuffer|nil instance Browse buffer or nil on error
function BrowseBuffer.open()
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

	-- Create new instance (no has_changes gate for browse mode)
	local instance = BrowseBuffer.new(repo)
	instances[root] = instance

	return instance
end

---Create a new browse buffer
---@param repo VcsBackend VCS backend
---@return BrowseBuffer instance
function BrowseBuffer.new(repo)
	local instance = setmetatable({
		repo = repo,
	}, BrowseBuffer)

	-- Create session (no base_ref needed for browse mode)
	instance.session = Session.load_or_create(repo:get_root(), repo:get_head())

	-- Get tracked files
	local tracked_files = repo:get_tracked_files()

	-- Ensure files are tracked in session (no diff hashing for browse mode)
	local files = {}
	for _, file in ipairs(tracked_files) do
		instance.session:ensure_file(file.path, file.status, nil)
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
function BrowseBuffer:_create_layout(files)
	-- Create new tab
	vim.cmd("tabnew")
	self.tab_page = vim.api.nvim_get_current_tabpage()

	-- Create vertical split
	vim.cmd("vsplit")

	-- Get window handles
	local wins = vim.api.nvim_tabpage_list_wins(self.tab_page)
	self.file_tree_win = wins[1]
	self.file_view_win = wins[2]

	-- Set file tree width to ~25%
	local total_width = vim.o.columns
	local file_tree_width = math.max(30, math.floor(total_width * 0.25))
	vim.api.nvim_win_set_width(self.file_tree_win, file_tree_width)

	-- Create file tree buffer
	vim.api.nvim_set_current_win(self.file_tree_win)
	self.file_tree = FileTreeBuffer.new({
		files = files,
		session = self.session,
		branch = self.repo:get_branch(),
	})
	self.file_tree:show()

	-- Subscribe to file tree events
	self.file_tree.events:on("file_select", function(file)
		self:_on_file_select(file)
	end)
	self.file_tree.events:on("open_file", function(file)
		self:_on_open_file(file)
	end)

	-- Create file view buffer
	vim.api.nvim_set_current_win(self.file_view_win)
	self.file_view = FileViewBuffer.new({
		repo = self.repo,
		session = self.session,
	})
	self.file_view:show()

	-- Subscribe to file view events
	self.file_view.events:on("comment", function(context)
		self:_on_add_comment(context)
	end)
	self.file_view.events:on("edit_comment", function(comment)
		self:_on_edit_comment(comment)
	end)
	self.file_view.events:on("toggle_reviewed", function(file)
		self:_on_toggle_reviewed(file)
	end)
	self.file_view.events:on("open_file", function(file, line)
		self:_on_open_file(file, line)
	end)
	self.file_view.events:on("quit", function()
		self:close()
	end)

	-- Setup tab-level keymappings
	self:_setup_tab_mappings()

	-- Select first file
	local first_file = self.file_tree:get_current_file()
	if first_file then
		self:_on_file_select(first_file)
	end

	-- Focus file tree initially
	vim.api.nvim_set_current_win(self.file_tree_win)

	self:_start_watching()
end

---Watch the repository so an agent's edits land in the view without a keypress.
---
---Unlike review mode there is no per-file watching here: browse mode lists every
---tracked file, which is far past the watcher's cap, and none of them are
---especially interesting. The VCS metadata poller is what matters — it catches
---files being added to or removed from the repository.
function BrowseBuffer:_start_watching()
	if require("oversight").config.watch == false then
		return
	end

	require("oversight.lib.watcher").attach(self.repo:get_root(), self.repo.type, {
		on_change = function()
			if not self:is_valid() then
				return
			end
			self:refresh({ silent = true })
		end,
		-- Browse mode's tree is the tracked-file list, so that is what has to
		-- move for the view to be stale — the file *contents* are re-read on
		-- every refresh anyway.
		probe = function()
			local parts = {}
			for _, file in ipairs(self.repo:get_tracked_files()) do
				table.insert(parts, file.path)
			end
			return table.concat(parts, "\n")
		end,
	})
end

---Setup tab-level keymappings
function BrowseBuffer:_setup_tab_mappings()
	local group = vim.api.nvim_create_augroup("oversight_browse_" .. self.tab_page, { clear = true })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function()
			local buf = vim.api.nvim_get_current_buf()
			local file_tree_buf = self.file_tree:get_handle()
			local file_view_buf = self.file_view:get_handle()

			if buf == file_tree_buf or buf == file_view_buf then
				vim.keymap.set("n", "<Tab>", function()
					self:_toggle_focus()
				end, { buffer = buf, desc = "Toggle panel focus" })

				vim.keymap.set("n", "{", function()
					self:_navigate_file(-1)
				end, { buffer = buf, desc = "Previous file" })

				vim.keymap.set("n", "}", function()
					self:_navigate_file(1)
				end, { buffer = buf, desc = "Next file" })

				vim.keymap.set("n", "y", function()
					self:export_markdown()
				end, { buffer = buf, desc = "Yank comments to clipboard" })

				vim.keymap.set("n", "X", function()
					self:clear_comments()
				end, { buffer = buf, desc = "Clear all comments" })

				vim.keymap.set("n", "R", function()
					self:refresh()
				end, { buffer = buf, desc = "Refresh" })

				vim.keymap.set("n", "?", function()
					self:show_help()
				end, { buffer = buf, desc = "Show help" })

				vim.keymap.set("n", "q", function()
					self:close()
				end, { buffer = buf, desc = "Quit browse" })
			end
		end,
	})
end

---Handle file selection
---@param file File Selected file
function BrowseBuffer:_on_file_select(file)
	self.file_view:show_file(file)
end

---Handle opening file in editor
---@param file File File to open
---@param line number|nil Optional line number to jump to
function BrowseBuffer:_on_open_file(file, line)
	local full_path = self.repo:get_root() .. "/" .. file.path
	vim.cmd("tabnew " .. vim.fn.fnameescape(full_path))
	if line then
		vim.api.nvim_win_set_cursor(0, { line, 0 })
	end
end

---Handle toggling reviewed status from file view
---@param file File File that was toggled
function BrowseBuffer:_on_toggle_reviewed(file)
	self.file_tree:update_file_reviewed(file.path, file.reviewed)
end

---Handle adding a comment
---@param context CommentContext Comment context
function BrowseBuffer:_on_add_comment(context)
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
		self.file_view:render()
		vim.notify("Comment added", vim.log.levels.INFO)
	end)
end

---Handle editing an existing comment
---@param comment Comment Comment to edit
function BrowseBuffer:_on_edit_comment(comment)
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
		self.file_view:render()
		vim.notify("Comment updated", vim.log.levels.INFO)
	end)
end

---Toggle focus between panels
function BrowseBuffer:_toggle_focus()
	if not vim.api.nvim_win_is_valid(self.file_tree_win) or not vim.api.nvim_win_is_valid(self.file_view_win) then
		return
	end

	local current_win = vim.api.nvim_get_current_win()
	if current_win == self.file_tree_win then
		vim.api.nvim_set_current_win(self.file_view_win)
		self.file_view:jump_to_first_content()
	else
		vim.api.nvim_set_current_win(self.file_tree_win)
	end
end

---Navigate to next/previous file in tree
---@param delta number 1 for next, -1 for previous
function BrowseBuffer:_navigate_file(delta)
	self.file_tree:move_cursor(delta)
end

---Export review to markdown and copy to clipboard
function BrowseBuffer:export_markdown()
	if not self.session:has_comments() then
		vim.notify("No comments to export", vim.log.levels.WARN)
		return
	end

	local Export = require("oversight.lib.export")
	local markdown = Export.to_markdown(self.session, self.repo, { title = "Codebase Notes" })

	vim.fn.setreg("+", markdown)
	vim.fn.setreg("*", markdown)

	local counts = self.session:get_comment_counts()
	local total = counts.note + counts.suggestion + counts.issue + counts.praise
	vim.notify(string.format("Exported %d comments to clipboard", total), vim.log.levels.INFO)
end

---Clear all comments with confirmation
function BrowseBuffer:clear_comments()
	if not self.session:has_comments() then
		vim.notify("No comments to clear", vim.log.levels.INFO)
		return
	end

	local counts = self.session:get_comment_counts()
	local total = counts.note + counts.suggestion + counts.issue + counts.praise

	vim.ui.select({ "Yes", "No" }, {
		prompt = string.format("Clear all %d comments? ", total),
	}, function(choice)
		if choice == "Yes" then
			self.session.comments = {}
			self.session:save()
			self.file_view:render()
			vim.notify(string.format("Cleared %d comments", total), vim.log.levels.INFO)
		end
	end)
end

---Show help overlay
function BrowseBuffer:show_help()
	-- Browse mode must ask for its own text. The overlay's default is the review
	-- one, which talks about hunks that do not exist here and omits `l`/`h`.
	HelpOverlay.show({ help_text = HelpOverlay.BROWSE_HELP_TEXT, title = " Browse Help " })
end

---Refresh the file tree with latest tracked files
---@param opts? RefreshOpts
function BrowseBuffer:refresh(opts)
	opts = opts or {}

	local files = {}

	-- See ReviewBuffer:refresh — reading a jj repository writes to it.
	require("oversight.lib.watcher").while_refreshing(self.repo:get_root(), function()
		local tracked_files = self.repo:get_tracked_files()

		for _, file in ipairs(tracked_files) do
			self.session:ensure_file(file.path, file.status, nil)
			local status = self.session:get_file_status(file.path)
			table.insert(files, {
				path = file.path,
				status = file.status,
				reviewed = status and status.reviewed or false,
			})
		end
	end)

	self.file_tree:set_files(files)

	local current_file = self.file_tree:get_current_file()
	if current_file then
		-- Drop the cached contents so an externally-edited file is re-read.
		self.file_view.file_cache[current_file.path] = nil
		self.file_view:show_file(current_file)
	end

	require("oversight.lib.watcher").sync_probe(self.repo:get_root())

	if not opts.silent then
		vim.notify("Refreshed", vim.log.levels.INFO)
	end
end

---Check if browse is still valid
---@return boolean valid True if tab and windows are valid
function BrowseBuffer:is_valid()
	-- `and` yields the last truthy operand, so without the coercion this
	-- returned a FileViewBuffer rather than the boolean the signature promises.
	-- `not not` rather than `~= nil`: nvim_tabpage_is_valid returns false, and
	-- `false ~= nil` would wrongly report a closed tab as valid.
	return not not (
		self.tab_page
		and vim.api.nvim_tabpage_is_valid(self.tab_page)
		and self.file_tree
		and self.file_view
	)
end

---Focus the browse tab
function BrowseBuffer:focus()
	if self.tab_page and vim.api.nvim_tabpage_is_valid(self.tab_page) then
		vim.api.nvim_set_current_tabpage(self.tab_page)
	end
end

---Close the browse interface
function BrowseBuffer:close()
	if self.session then
		self.session:save()
	end

	-- Refcounted, so this only tears the pollers down if review mode is not also
	-- open on the same repository.
	if self.repo then
		require("oversight.lib.watcher").detach(self.repo:get_root())
	end

	if self.file_tree then
		self.file_tree:close()
	end
	if self.file_view then
		self.file_view:close()
	end

	if self.repo then
		instances[self.repo:get_root()] = nil
	end

	if self.tab_page and vim.api.nvim_tabpage_is_valid(self.tab_page) then
		local current_tab = vim.api.nvim_get_current_tabpage()
		if current_tab == self.tab_page then
			vim.cmd("tabprevious")
		end
		local wins = vim.api.nvim_tabpage_list_wins(self.tab_page)
		for _, win in ipairs(wins) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
	end

	vim.notify("Browse closed", vim.log.levels.INFO)
end

---Close all browse instances
function BrowseBuffer.close_all()
	for _, instance in pairs(instances) do
		instance:close()
	end
	instances = {}
end

return BrowseBuffer
