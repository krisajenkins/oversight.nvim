-- Floating window helper
-- Shared logic for creating centered floating windows

local M = {}

---@class FloatOpts
---@field width number Window width
---@field height number Window height
---@field title? string Window title (shown in border)
---@field modifiable? boolean Whether buffer is modifiable (default false)
---@field filetype? string Buffer filetype

---@class FloatState
---@field buf number Buffer handle
---@field win number Window handle

---Open a centered floating window with a scratch buffer
---@param opts FloatOpts Options
---@return FloatState state Buffer and window handles
function M.open(opts)
	-- Create scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	if opts.filetype then
		vim.api.nvim_set_option_value("filetype", opts.filetype, { buf = buf })
	end

	if opts.modifiable == false then
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end

	-- Center the window
	local row = math.floor((vim.o.lines - opts.height) / 2)
	local col = math.floor((vim.o.columns - opts.width) / 2)

	-- Open window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = opts.width,
		height = opts.height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = opts.title,
		title_pos = opts.title and "center" or nil,
	})

	return { buf = buf, win = win }
end

---Close a floating window
---@param state FloatState State returned from open()
function M.close(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
end

return M
