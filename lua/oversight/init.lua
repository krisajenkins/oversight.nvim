-- oversight - Code review plugin for Neovim
-- Main entry point and public API

local M = {}

---@class OversightConfig
---@field data_dir? string Override XDG data directory for session storage

---@type OversightConfig
M.config = {}

--- Setup oversight with optional configuration
---@param opts? OversightConfig
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Setup highlights
	require("oversight.highlights").setup()

	-- Register :Oversight command
	vim.api.nvim_create_user_command("Oversight", function(cmd_opts)
		M.open_review(cmd_opts.args ~= "" and cmd_opts.args or nil)
	end, {
		nargs = "?",
		desc = "Open oversight code review",
		complete = "dir",
	})
end

--- Open the code review interface
---@param dir? string Directory to review (defaults to cwd)
function M.open_review(dir)
	local ReviewBuffer = require("oversight.buffers.review")
	ReviewBuffer.open(dir)
end

--- Close any open review buffers
function M.close()
	local ReviewBuffer = require("oversight.buffers.review")
	ReviewBuffer.close_all()
end

return M
