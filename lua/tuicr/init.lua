-- tuicr - Code review plugin for Neovim
-- Main entry point and public API

local M = {}

---@class TuicrConfig
---@field data_dir? string Override XDG data directory for session storage

---@type TuicrConfig
M.config = {}

--- Setup tuicr with optional configuration
---@param opts? TuicrConfig
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Setup highlights
	require("tuicr.highlights").setup()

	-- Register :Tuicr command
	vim.api.nvim_create_user_command("Tuicr", function(cmd_opts)
		M.open_review(cmd_opts.args ~= "" and cmd_opts.args or nil)
	end, {
		nargs = "?",
		desc = "Open tuicr code review",
		complete = "dir",
	})
end

--- Open the code review interface
---@param dir? string Directory to review (defaults to cwd)
function M.open_review(dir)
	local ReviewBuffer = require("tuicr.buffers.review")
	ReviewBuffer.open(dir)
end

--- Close any open review buffers
function M.close()
	local ReviewBuffer = require("tuicr.buffers.review")
	ReviewBuffer.close_all()
end

return M
