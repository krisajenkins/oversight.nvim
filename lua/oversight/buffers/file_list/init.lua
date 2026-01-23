-- File list buffer controller

local Buffer = require("oversight.lib.buffer")
local EventEmitter = require("oversight.lib.events")
local FileListUI = require("oversight.buffers.file_list.ui")

-- Events emitted by FileListBuffer:
---@alias FileListBufferEvent
---| "file_select" # (file: File, index: number) - File was selected or navigated to
---| "toggle_reviewed" # (file: File, index: number) - File reviewed status was toggled
---| "open_file" # (file: File, index: number) - Request to open file in editor

---@class FileListBufferOpts
---@field files File[] List of files
---@field session ReviewSession Review session
---@field branch? string Current branch name

---@class FileListBuffer
---@field buffer Buffer Buffer instance
---@field events EventEmitter Event emitter for decoupled communication
---@field files File[] List of files
---@field current_path string|nil Path of currently selected file
---@field session ReviewSession Review session
---@field branch? string Current branch name
local FileListBuffer = {}
FileListBuffer.__index = FileListBuffer

---Create a new file list buffer
---@param opts FileListBufferOpts Options
---@return FileListBuffer instance
function FileListBuffer.new(opts)
	local files = opts.files or {}
	local instance = setmetatable({
		files = files,
		current_path = files[1] and files[1].path or nil,
		session = opts.session,
		branch = opts.branch,
		events = EventEmitter.new(),
	}, FileListBuffer)

	instance.buffer = Buffer.new({
		name = "oversight://files",
		filetype = "oversight-files",
		modifiable = false,
		readonly = true,
	})

	instance:_setup_mappings()

	return instance
end

---Get files split into unreviewed and reviewed lists
---@return File[] unreviewed Unreviewed files
---@return File[] reviewed Reviewed files
function FileListBuffer:_get_split_files()
	local unreviewed = {}
	local reviewed = {}
	for _, file in ipairs(self.files) do
		if file.reviewed then
			table.insert(reviewed, file)
		else
			table.insert(unreviewed, file)
		end
	end
	return unreviewed, reviewed
end

---Get files in display order (unreviewed first, then reviewed)
---@return File[] display_files Files in display order
function FileListBuffer:_get_display_order()
	local unreviewed, reviewed = self:_get_split_files()
	local display = {}
	for _, file in ipairs(unreviewed) do
		table.insert(display, file)
	end
	for _, file in ipairs(reviewed) do
		table.insert(display, file)
	end
	return display
end

---Get display index for a file path
---@param path string|nil File path to find
---@return number|nil index Display index (1-indexed) or nil if not found
function FileListBuffer:_get_display_index(path)
	if not path then
		return nil
	end
	local display_files = self:_get_display_order()
	for i, file in ipairs(display_files) do
		if file.path == path then
			return i
		end
	end
	return nil
end

---Get file at display index
---@param display_index number Display index (1-indexed)
---@return File|nil file File at that index or nil
function FileListBuffer:_get_file_at_display_index(display_index)
	local display_files = self:_get_display_order()
	return display_files[display_index]
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
		local display_files = self:_get_display_order()
		self:move_to(#display_files)
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

---Move cursor by delta in display order
---@param delta number Number of files to move (positive = down)
function FileListBuffer:move_cursor(delta)
	local display_files = self:_get_display_order()
	if #display_files == 0 then
		return
	end

	local current_index = self:_get_display_index(self.current_path) or 1
	local new_index = current_index + delta
	new_index = math.max(1, math.min(new_index, #display_files))

	local new_file = display_files[new_index]
	if new_file and new_file.path ~= self.current_path then
		self.current_path = new_file.path
		self:render()

		-- Notify about selection change
		self.events:emit("file_select", new_file, new_index)
	end
end

---Move to specific display index
---@param index number Target display index
function FileListBuffer:move_to(index)
	local display_files = self:_get_display_order()
	if #display_files == 0 then
		return
	end

	index = math.max(1, math.min(index, #display_files))
	local new_file = display_files[index]

	if new_file and new_file.path ~= self.current_path then
		self.current_path = new_file.path
		self:render()

		self.events:emit("file_select", new_file, index)
	end
end

---Select current file
function FileListBuffer:select_file()
	local file = self:get_current_file()
	if file then
		local index = self:_get_display_index(self.current_path) or 1
		self.events:emit("file_select", file, index)
	end
end

---Open current file in editor
function FileListBuffer:open_file()
	local file = self:get_current_file()
	if file then
		local index = self:_get_display_index(self.current_path) or 1
		self.events:emit("open_file", file, index)
	end
end

---Toggle reviewed status for current file
function FileListBuffer:toggle_reviewed()
	local file = self:get_current_file()
	if file then
		-- Remember current display position
		local old_display_index = self:_get_display_index(self.current_path) or 1

		file.reviewed = not file.reviewed

		-- Update session
		if self.session then
			self.session:set_file_reviewed(file.path, file.reviewed)
			self.session:save()
		end

		-- Keep cursor at same screen position (or end of list if was at end)
		local display_files = self:_get_display_order()
		local new_index = math.min(old_display_index, #display_files)
		local new_file = display_files[new_index]
		if new_file then
			self.current_path = new_file.path
		end

		self:render()

		self.events:emit("toggle_reviewed", file, new_index)

		-- Notify about new selection
		local current = self:get_current_file()
		if current then
			self.events:emit("file_select", current, new_index)
		end
	end
end

---Update files list
---@param files File[] New files list
function FileListBuffer:set_files(files)
	self.files = files
	-- Keep current selection if file still exists, otherwise select first file
	local found = false
	for _, file in ipairs(files) do
		if file.path == self.current_path then
			found = true
			break
		end
	end
	if not found then
		self.current_path = files[1] and files[1].path or nil
	end
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
	if not self.current_path then
		return nil
	end
	for _, file in ipairs(self.files) do
		if file.path == self.current_path then
			return file
		end
	end
	return nil
end

---Get current display index
---@return number index Current display index
function FileListBuffer:get_current_index()
	return self:_get_display_index(self.current_path) or 1
end

---Render the file list
function FileListBuffer:render()
	-- Split files into sections
	local unreviewed, reviewed = self:_get_split_files()
	local total = #self.files
	local reviewed_count = #reviewed

	local components = {}

	-- Header
	table.insert(components, FileListUI.create_header(reviewed_count, total, self.branch))

	-- File list with two sections
	local file_components, selected_line = FileListUI.create(unreviewed, reviewed, self.current_path)
	for _, comp in ipairs(file_components) do
		table.insert(components, comp)
	end

	self.buffer:render(components)

	-- Position cursor on current line (header is 3 lines)
	if selected_line then
		local cursor_line = 3 + selected_line
		self.buffer:set_cursor(cursor_line, 0)
	end
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
	self.events:clear()
	self.buffer:close()
end

return FileListBuffer
