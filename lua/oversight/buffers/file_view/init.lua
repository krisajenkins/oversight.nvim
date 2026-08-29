-- File view buffer controller (browse mode right panel)
-- Shows full file content with line numbers and inline comments

local Buffer = require("oversight.lib.buffer")
local EventEmitter = require("oversight.lib.events")
local Binary = require("oversight.lib.binary")
local FileViewUI = require("oversight.buffers.file_view.ui")

-- Events emitted by FileViewBuffer:
---@alias FileViewBufferEvent
---| "comment" # (context: CommentContext) - Request to add a comment
---| "edit_comment" # (comment: Comment) - Request to edit existing comment
---| "toggle_reviewed" # (file: File) - File reviewed status was toggled
---| "open_file" # (file: File, line: number|nil) - Request to open file at line
---| "quit" # () - Request to close

---@class FileViewBufferOpts
---@field repo VcsBackend VCS backend
---@field session ReviewSession Review session

---@class FileViewBuffer
---@field buffer Buffer Buffer instance
---@field events EventEmitter Event emitter
---@field repo VcsBackend VCS backend
---@field session ReviewSession Review session
---@field current_file File|nil Current file being displayed
---@field file_cache table<string, string[]> Cached file contents
local FileViewBuffer = {}
FileViewBuffer.__index = FileViewBuffer

---Create a new file view buffer
---@param opts FileViewBufferOpts Options
---@return FileViewBuffer instance
function FileViewBuffer.new(opts)
	local instance = setmetatable({
		repo = opts.repo,
		session = opts.session,
		current_file = nil,
		file_cache = {},
		events = EventEmitter.new(),
	}, FileViewBuffer)

	instance.buffer = Buffer.new({
		name = "oversight://file-view",
		filetype = "oversight-file-view",
		modifiable = false,
		readonly = true,
	})

	instance:_setup_mappings()

	return instance
end

---Setup keymappings for the buffer
function FileViewBuffer:_setup_mappings()
	local buf = self.buffer

	-- Scrolling
	buf:map("n", "j", function()
		vim.cmd("normal! j")
	end, { desc = "Scroll down" })

	buf:map("n", "k", function()
		vim.cmd("normal! k")
	end, { desc = "Scroll up" })

	buf:map("n", "<Down>", function()
		vim.cmd("normal! j")
	end, { desc = "Scroll down" })

	buf:map("n", "<Up>", function()
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

	-- Comment actions
	buf:map("n", "c", function()
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

---Show a file's content
---@param file File File info
function FileViewBuffer:show_file(file)
	self.current_file = file

	-- Read file if not cached
	if not self.file_cache[file.path] then
		local lines = self.repo:read_file(file.path)
		if lines then
			self.file_cache[file.path] = lines
		end
	end

	self:render()
end

---Render the file view
function FileViewBuffer:render()
	if not self.current_file then
		local Ui = require("oversight.lib.ui")
		self.buffer:render({
			Ui.text("Select a file to view", { highlight = "Comment" }),
		})
		return
	end

	local lines = self.file_cache[self.current_file.path]
	if not lines then
		local Ui = require("oversight.lib.ui")
		self.buffer:render({
			Ui.text("Could not read " .. self.current_file.path, { highlight = "Comment" }),
		})
		return
	end

	local reviewed = self.current_file.reviewed or false
	local components = {}

	-- Keybindings hint
	table.insert(components, FileViewUI.create_keybindings_hint())

	-- File header
	table.insert(components, FileViewUI.create_file_header(self.current_file.path, reviewed))

	-- Binary detection. Sniffed on disk rather than over `lines`, because the
	-- readfile those came from has already turned every NUL into a newline.
	if Binary.file_is_binary(self.repo:get_root() .. "/" .. self.current_file.path) then
		table.insert(components, FileViewUI.create_binary_notice(self.current_file.path))
		self.buffer:render(components)
		return
	end

	-- Get comments for this file
	local comments = {}
	if self.session then
		comments = self.session:get_file_comments(self.current_file.path)
	end

	-- Build comment lookup by line
	local line_comments = {}
	for _, comment in ipairs(comments) do
		if comment.line then
			line_comments[comment.line] = line_comments[comment.line] or {}
			table.insert(line_comments[comment.line], comment)
		end
	end

	-- Track source line -> buffer line mapping for syntax highlighting
	-- Buffer lines: 0=hint, 1=header, 2+=content
	local line_map = {}
	local buf_line = 2

	-- Render each line with interleaved comments
	for i, line in ipairs(lines) do
		local has_comment = line_comments[i] ~= nil
		table.insert(components, FileViewUI.create_file_line(i, line, has_comment))

		-- Record mapping: prefix is "%4d │ " = format(4+ chars) + " │ "(5 bytes)
		local prefix_len = #string.format("%4d", i) + 5
		line_map[i] = { buffer_line = buf_line, prefix_len = prefix_len }
		buf_line = buf_line + 1

		-- Add comments after their target lines
		if line_comments[i] then
			for _, comment in ipairs(line_comments[i]) do
				table.insert(components, FileViewUI.create_comment(comment))
				buf_line = buf_line + 1
			end
		end
	end

	-- Add file-level comments at the end
	for _, comment in ipairs(comments) do
		if not comment.line then
			table.insert(components, FileViewUI.create_comment(comment))
		end
	end

	self.buffer:render(components)

	-- Apply treesitter syntax highlighting over the rendered content
	self:_apply_syntax_highlights(lines, line_map)
end

---Apply treesitter syntax highlighting to rendered file content
---@param source_lines string[] Original file lines
---@param line_map table<number, table> Map of source line (1-indexed) to {buffer_line, prefix_len}
function FileViewBuffer:_apply_syntax_highlights(source_lines, line_map)
	if not self.current_file or not source_lines or #source_lines == 0 then
		return
	end

	-- Detect filetype from path
	local ft = vim.filetype.match({ filename = self.current_file.path })
	if not ft then
		return
	end

	-- Get treesitter language for this filetype
	local lang = vim.treesitter.language.get_lang(ft) or ft

	-- Check if parser is available
	local ok = pcall(vim.treesitter.language.add, lang)
	if not ok then
		return
	end

	-- Parse source
	local source = table.concat(source_lines, "\n")
	local parser_ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
	if not parser_ok or not parser then
		return
	end

	local trees = parser:parse()
	if not trees or #trees == 0 then
		return
	end

	-- Get highlights query
	local query = vim.treesitter.query.get(lang, "highlights")
	if not query then
		return
	end

	-- Apply highlights with a dedicated namespace (higher priority than component highlights)
	local buf = self.buffer:get_handle()
	local ns = vim.api.nvim_create_namespace("oversight_syntax")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	for _, tree in ipairs(trees) do
		for id, node in query:iter_captures(tree:root(), source) do
			local name = query.captures[id]
			local hl_group = "@" .. name .. "." .. lang

			local start_row, start_col, end_row, end_col = node:range()

			-- Map each line of the capture to the display buffer
			for src_row = start_row, end_row do
				local mapping = line_map[src_row + 1]
				if mapping then
					local cap_start = (src_row == start_row) and start_col or 0
					local cap_end = (src_row == end_row) and end_col or #(source_lines[src_row + 1] or "")

					pcall(vim.api.nvim_buf_set_extmark, buf, ns, mapping.buffer_line, mapping.prefix_len + cap_start, {
						end_col = mapping.prefix_len + cap_end,
						hl_group = hl_group,
						priority = 200,
					})
				end
			end
		end
	end
end

---Get line info at cursor
---@return LineInfo|nil info Line info or nil
function FileViewBuffer:_get_line_at_cursor()
	local component = self.buffer:get_component_at_cursor()
	if component and component:is_interactive() then
		return component:get_item()
	end
	return nil
end

---Add a line comment
function FileViewBuffer:add_line_comment()
	if not self.current_file then
		return
	end

	local item = self:_get_line_at_cursor()
	if not item or item.type ~= "file_line" then
		vim.notify("Position cursor on a line to add a comment", vim.log.levels.WARN)
		return
	end

	self.events:emit("comment", {
		file = self.current_file.path,
		line = item.line_no,
		side = nil,
	})
end

---Add a file-level comment
function FileViewBuffer:add_file_comment()
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
function FileViewBuffer:delete_comment()
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
---@return boolean edited True if a comment was edited
function FileViewBuffer:edit_comment()
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
function FileViewBuffer:toggle_reviewed()
	if not self.current_file then
		return
	end

	if self.session then
		local new_status = self.session:toggle_file_reviewed(self.current_file.path)
		self.session:save()

		self.current_file.reviewed = new_status
		self:render()

		self.events:emit("toggle_reviewed", self.current_file)

		local status_text = new_status and "reviewed" or "not reviewed"
		vim.notify(self.current_file.path .. " marked as " .. status_text, vim.log.levels.INFO)
	end
end

---Open the current file in editor at the line under cursor
function FileViewBuffer:open_file()
	if not self.current_file then
		return
	end

	local item = self:_get_line_at_cursor()
	local line_no = nil
	if item and item.type == "file_line" then
		line_no = item.line_no
	end

	self.events:emit("open_file", self.current_file, line_no)
end

---Jump to first content line (skipping keybindings hint and header)
function FileViewBuffer:jump_to_first_content()
	local lines = self.buffer:get_lines(0, 10)
	for i, line in ipairs(lines) do
		if line:match("^===") then
			self.buffer:set_cursor(i, 0)
			return
		end
	end
	if #lines >= 2 then
		self.buffer:set_cursor(2, 0)
	end
end

---Show the buffer in the current window
function FileViewBuffer:show()
	self.buffer:show()
	self:render()
end

---Get buffer handle
---@return number handle Buffer handle
function FileViewBuffer:get_handle()
	return self.buffer:get_handle()
end

---Close the buffer
function FileViewBuffer:close()
	self.events:clear()
	self.buffer:close()
end

return FileViewBuffer
