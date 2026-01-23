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
	vim.api.nvim_create_user_command("Oversight", function()
		M.open_review()
	end, {
		desc = "Open oversight code review",
	})
end

--- Open the code review interface
function M.open_review()
	local ReviewBuffer = require("oversight.buffers.review")
	ReviewBuffer.open()
end

--- Close any open review buffers
function M.close()
	local ReviewBuffer = require("oversight.buffers.review")
	ReviewBuffer.close_all()
end

return M
