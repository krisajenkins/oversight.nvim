local Renderer = require("oversight.lib.ui.renderer")

---@class Buffer
---@field handle number Buffer handle
---@field name string Buffer name
---@field filetype string Buffer filetype
---@field mappings table Key mappings
---@field autocmds table[] Auto commands
---@field components table[] UI components
---@field config table Buffer configuration
local Buffer = {}
Buffer.__index = Buffer

---@class BufferConfig
---@field name string Buffer name
---@field filetype string Buffer filetype
---@field mappings? table Key mappings
---@field autocmds? table[] Auto commands
---@field modifiable? boolean Whether buffer is modifiable
---@field readonly? boolean Whether buffer is readonly
---@field unlisted? boolean Whether buffer is unlisted
---@field scratch? boolean Whether buffer is scratch

---Get existing buffer by name or create new one
---@param name string Buffer name
---@return number buffer_handle Buffer handle
function Buffer.from_name(name)
	local buffer_handle = vim.fn.bufnr(name)
	if buffer_handle == -1 then
		buffer_handle = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buffer_handle, name)
	end
	return buffer_handle
end

---Create a new buffer
---@param config BufferConfig Buffer configuration
---@return Buffer buffer Buffer instance
function Buffer.new(config)
	local buffer = Buffer.from_name(config.name)

	local instance = setmetatable({
		handle = buffer,
		name = config.name,
		filetype = config.filetype,
		mappings = config.mappings or {},
		autocmds = config.autocmds or {},
		components = {},
		component_positions = {},
		config = config,
	}, Buffer)

	instance:_setup_buffer()

	return instance
end

---Setup buffer properties and options
function Buffer:_setup_buffer()
	-- Set buffer name
	if self.name then
		vim.api.nvim_buf_set_name(self.handle, self.name)
	end

	-- Set buffer-local options
	local buffer_opts = {
		filetype = self.filetype,
		modifiable = self.config.modifiable ~= false,
		readonly = self.config.readonly == true,
		bufhidden = "wipe",
		buftype = "nofile",
		swapfile = false,
	}

	for option, value in pairs(buffer_opts) do
		vim.api.nvim_set_option_value(option, value, { buf = self.handle })
	end

	-- Set window-local options (these need to be set per window)
	local window_opts = {
		wrap = false,
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		colorcolumn = "",
		spell = false,
		list = false,
		conceallevel = 0,
		concealcursor = "",
		cursorline = true,
		cursorcolumn = false,
		scrolloff = 5,
		sidescrolloff = 5,
	}

	-- Store window options for later use
	self.window_opts = window_opts

	-- Apply window options to any windows displaying this buffer
	local windows = vim.fn.win_findbuf(self.handle)
	for _, win in ipairs(windows) do
		for option, value in pairs(window_opts) do
			vim.api.nvim_set_option_value(option, value, { win = win })
		end
	end

	-- Set up key mappings
	self:_setup_mappings()

	-- Set up autocmds
	self:_setup_autocmds()
end

---Setup key mappings for the buffer
function Buffer:_setup_mappings()
	-- Block insert mode if buffer is non-modifiable
	if self.config.modifiable == false then
		local insert_keys = { "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "R" }
		for _, key in ipairs(insert_keys) do
			vim.keymap.set("n", key, "<Nop>", { buffer = self.handle, silent = true })
		end
	end

	for mode, mode_mappings in pairs(self.mappings) do
		for key, mapping in pairs(mode_mappings) do
			local opts = {
				buffer = self.handle,
				nowait = true,
				silent = true,
			}

			if type(mapping) == "table" then
				opts = vim.tbl_extend("force", opts, mapping.opts or {})
				vim.keymap.set(mode, key, mapping.callback or mapping[1], opts)
			else
				vim.keymap.set(mode, key, mapping, opts)
			end
		end
	end
end

---Setup autocmds for the buffer
function Buffer:_setup_autocmds()
	local augroup = vim.api.nvim_create_augroup("oversight_buffer_" .. self.handle, { clear = true })

	-- Add autocmd to set window options when buffer is displayed
	if self.window_opts then
		vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
			group = augroup,
			buffer = self.handle,
			callback = function()
				local win = vim.api.nvim_get_current_win()
				for option, value in pairs(self.window_opts) do
					vim.api.nvim_set_option_value(option, value, { win = win })
				end
			end,
		})
	end

	for _, autocmd in ipairs(self.autocmds) do
		vim.api.nvim_create_autocmd(autocmd.event, {
			group = augroup,
			buffer = self.handle,
			callback = autocmd.callback,
			pattern = autocmd.pattern,
			once = autocmd.once,
		})
	end
end

---Render components to the buffer
---@param components table[] Components to render
function Buffer:render(components)
	self.components = components

	-- Temporarily disable readonly and make buffer modifiable
	vim.api.nvim_set_option_value("readonly", false, { buf = self.handle })
	vim.api.nvim_set_option_value("modifiable", true, { buf = self.handle })

	-- Render components and capture positions
	self.component_positions = Renderer.render_to_buffer(self.handle, components)

	-- Restore original buffer state
	vim.api.nvim_set_option_value("modifiable", self.config.modifiable ~= false, { buf = self.handle })
	vim.api.nvim_set_option_value("readonly", self.config.readonly == true, { buf = self.handle })
end

---Show the buffer in the current window
function Buffer:show()
	vim.api.nvim_set_current_buf(self.handle)
end

---Show the buffer in a new split
---@param split_type? string Split type ("horizontal" or "vertical")
function Buffer:show_split(split_type)
	if split_type == "vertical" then
		vim.cmd("vsplit")
	else
		vim.cmd("split")
	end
	vim.api.nvim_set_current_buf(self.handle)
end

---Show the buffer in a new tab
function Buffer:show_tab()
	vim.cmd("tabnew")
	vim.api.nvim_set_current_buf(self.handle)
end

---Close the buffer
function Buffer:close()
	if vim.api.nvim_buf_is_valid(self.handle) then
		vim.api.nvim_buf_delete(self.handle, { force = true })
	end
end

---Check if buffer is valid
---@return boolean valid True if buffer is valid
function Buffer:is_valid()
	return vim.api.nvim_buf_is_valid(self.handle)
end

---Get buffer handle
---@return number handle Buffer handle
function Buffer:get_handle()
	return self.handle
end

---Get buffer name
---@return string name Buffer name
function Buffer:get_name()
	return self.name
end

---Get current cursor position
---@return number[] position Line and column (1-indexed)
function Buffer:get_cursor()
	local windows = vim.fn.win_findbuf(self.handle)
	if #windows > 0 then
		return vim.api.nvim_win_get_cursor(windows[1])
	end
	return { 1, 0 }
end

---Set cursor position
---@param line number Line number (1-indexed)
---@param col number Column number (0-indexed)
function Buffer:set_cursor(line, col)
	local windows = vim.fn.win_findbuf(self.handle)
	if #windows > 0 then
		vim.api.nvim_win_set_cursor(windows[1], { line, col })
	end
end

---Get the component at the current cursor position
---@return table|nil component Component at cursor or nil
function Buffer:get_component_at_cursor()
	local line, _ = unpack(self:get_cursor())
	-- Convert to 0-indexed line number (renderer uses 0-indexed)
	local line_idx = line - 1

	-- Find the component at the current line or the closest preceding line
	for i = line_idx, 0, -1 do
		local component = self.component_positions[i]
		if component then
			return component
		end
	end

	return nil
end

---Refresh the buffer content
function Buffer:refresh()
	if #self.components > 0 then
		self:render(self.components)
	end
end

---Add a key mapping to the buffer
---@param mode string|table Mapping mode(s)
---@param key string Key sequence
---@param callback function|string Callback function or command
---@param opts? table Mapping options
function Buffer:map(mode, key, callback, opts)
	opts = opts or {}
	opts.buffer = self.handle
	opts.nowait = opts.nowait ~= false
	opts.silent = opts.silent ~= false

	vim.keymap.set(mode, key, callback, opts)
end

---Get window handle for this buffer
---@return number|nil win Window handle or nil if not displayed
function Buffer:get_window()
	local windows = vim.fn.win_findbuf(self.handle)
	if #windows > 0 then
		return windows[1]
	end
	return nil
end

---Set window width (if buffer is displayed)
---@param width number Width in columns
function Buffer:set_width(width)
	local win = self:get_window()
	if win then
		vim.api.nvim_win_set_width(win, width)
	end
end

---Get line count
---@return number count Number of lines in buffer
function Buffer:line_count()
	return vim.api.nvim_buf_line_count(self.handle)
end

---Get lines from buffer
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed, -1 for end)
---@return string[] lines Lines from buffer
function Buffer:get_lines(start_line, end_line)
	return vim.api.nvim_buf_get_lines(self.handle, start_line, end_line, false)
end

return Buffer
