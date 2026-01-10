-- File list buffer controller

local Buffer = require("tuicr.lib.buffer")
local FileListUI = require("tuicr.buffers.file_list.ui")

---@class FileListBufferOpts
---@field files File[] List of files
---@field session ReviewSession Review session
---@field branch? string Current branch name
---@field on_file_select? fun(file: File, index: number): nil Callback when file is selected
---@field on_toggle_reviewed? fun(file: File, index: number): nil Callback when file is toggled
---@field on_open_file? fun(file: File, index: number): nil Callback when file should be opened in editor

---@class FileListBuffer
---@field buffer Buffer Buffer instance
---@field files File[] List of files
---@field current_index number Currently selected file index
---@field session ReviewSession Review session
---@field branch? string Current branch name
---@field on_file_select? fun(file: File, index: number): nil Callback when file is selected
---@field on_toggle_reviewed? fun(file: File, index: number): nil Callback when file is toggled
---@field on_open_file? fun(file: File, index: number): nil Callback when file should be opened in editor
local FileListBuffer = {}
FileListBuffer.__index = FileListBuffer

---Create a new file list buffer
---@param opts FileListBufferOpts Options
---@return FileListBuffer instance
function FileListBuffer.new(opts)
	local instance = setmetatable({
		files = opts.files or {},
		current_index = 1,
		session = opts.session,
		on_file_select = opts.on_file_select,
		on_toggle_reviewed = opts.on_toggle_reviewed,
		on_open_file = opts.on_open_file,
		branch = opts.branch,
	}, FileListBuffer)

	instance.buffer = Buffer.new({
		name = "tuicr://files",
		filetype = "tuicr-files",
		modifiable = false,
		readonly = true,
	})

	instance:_setup_mappings()

	return instance
end

---Setup keymappings for the buffer
function FileListBuffer:_setup_mappings()
	local buf = self.buffer

	-- Navigation
	buf:map("n", "j", function()
		self:move_cursor(1)
	end, { desc = "Move down" })

	buf:map("n", "k", function()
		self:move_cursor(-1)
	end, { desc = "Move up" })

	buf:map("n", "g", function()
		self:move_to(1)
	end, { desc = "Go to first file" })

	buf:map("n", "G", function()
		self:move_to(#self.files)
	end, { desc = "Go to last file" })

	buf:map("n", "<CR>", function()
		self:select_file()
	end, { desc = "Select file" })

	buf:map("n", "o", function()
		self:open_file()
	end, { desc = "Open file in editor" })

	-- Review actions
	buf:map("n", "r", function()
		self:toggle_reviewed()
	end, { desc = "Toggle reviewed" })

	-- Half-page navigation
	buf:map("n", "<C-d>", function()
		local half = math.floor(vim.api.nvim_win_get_height(0) / 2)
		self:move_cursor(half)
	end, { desc = "Half page down" })

	buf:map("n", "<C-u>", function()
		local half = math.floor(vim.api.nvim_win_get_height(0) / 2)
		self:move_cursor(-half)
	end, { desc = "Half page up" })
end

---Move cursor by delta
---@param delta number Number of lines to move (positive = down)
function FileListBuffer:move_cursor(delta)
	local new_index = self.current_index + delta
	new_index = math.max(1, math.min(new_index, #self.files))

	if new_index ~= self.current_index then
		self.current_index = new_index
		self:render()

		-- Notify parent about selection change
		if self.on_file_select then
			local file = self.files[self.current_index]
			if file then
				self.on_file_select(file, self.current_index)
			end
		end
	end
end

---Move to specific index
---@param index number Target index
function FileListBuffer:move_to(index)
	index = math.max(1, math.min(index, #self.files))
	if index ~= self.current_index then
		self.current_index = index
		self:render()

		if self.on_file_select then
			local file = self.files[self.current_index]
			if file then
				self.on_file_select(file, self.current_index)
			end
		end
	end
end

---Select current file (trigger callback)
function FileListBuffer:select_file()
	if self.on_file_select then
		local file = self.files[self.current_index]
		if file then
			self.on_file_select(file, self.current_index)
		end
	end
end

---Open current file in editor
function FileListBuffer:open_file()
	local file = self.files[self.current_index]
	if file and self.on_open_file then
		self.on_open_file(file, self.current_index)
	end
end

---Toggle reviewed status for current file
function FileListBuffer:toggle_reviewed()
	local file = self.files[self.current_index]
	if file then
		file.reviewed = not file.reviewed

		-- Update session
		if self.session then
			self.session:set_file_reviewed(file.path, file.reviewed)
			self.session:save()
		end

		self:render()

		if self.on_toggle_reviewed then
			self.on_toggle_reviewed(file, self.current_index)
		end
	end
end

---Update files list
---@param files File[] New files list
function FileListBuffer:set_files(files)
	self.files = files
	self.current_index = math.min(self.current_index, math.max(1, #files))
	self:render()
end

---Update reviewed status for a file by path
---@param path string File path to update
---@param reviewed boolean New reviewed status
function FileListBuffer:update_file_reviewed(path, reviewed)
	for _, file in ipairs(self.files) do
		if file.path == path then
			file.reviewed = reviewed
			self:render()
			return
		end
	end
end

---Get current file
---@return File|nil file Current file or nil
function FileListBuffer:get_current_file()
	return self.files[self.current_index]
end

---Get current index
---@return number index Current index
function FileListBuffer:get_current_index()
	return self.current_index
end

---Render the file list
function FileListBuffer:render()
	-- Get review progress
	local reviewed, total = 0, #self.files
	for _, file in ipairs(self.files) do
		if file.reviewed then
			reviewed = reviewed + 1
		end
	end

	local components = {}

	-- Header
	table.insert(components, FileListUI.create_header(reviewed, total, self.branch))

	-- File list
	local file_components = FileListUI.create(self.files, self.current_index)
	for _, comp in ipairs(file_components) do
		table.insert(components, comp)
	end

	self.buffer:render(components)

	-- Position cursor on current line (header is 3 lines)
	local cursor_line = 3 + self.current_index
	self.buffer:set_cursor(cursor_line, 0)
end

---Show the buffer in the current window
function FileListBuffer:show()
	self.buffer:show()
	self:render()
end

---Get buffer handle
---@return number handle Buffer handle
function FileListBuffer:get_handle()
	return self.buffer:get_handle()
end

---Close the buffer
function FileListBuffer:close()
	self.buffer:close()
end

return FileListBuffer
