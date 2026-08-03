-- oversight - Code review plugin for Neovim
-- Main entry point and public API

local M = {}

---Configuration accepted by `setup()`. Empty for now: review sessions are held
---in memory only, so there is no data directory to configure, and colours are
---set by overriding the `Oversight*` highlight groups.
---@class OversightConfig

---@type OversightConfig
M.config = {}

--- Setup oversight with optional configuration
---@param opts? OversightConfig
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Setup highlights
	require("oversight.highlights").setup()

	local subcommands = { "review", "browse" }

	-- Register :Oversight command with optional subcommand
	vim.api.nvim_create_user_command("Oversight", function(cmd_opts)
		local subcmd = cmd_opts.args ~= "" and cmd_opts.args or "review"
		if subcmd == "review" then
			M.open_review()
		elseif subcmd == "browse" then
			M.open_browse()
		else
			vim.notify("Unknown subcommand: " .. subcmd .. ". Use 'review' or 'browse'.", vim.log.levels.ERROR)
		end
	end, {
		desc = "Open oversight code review or browse mode",
		nargs = "?",
		complete = function(arg_lead)
			return vim.tbl_filter(function(s)
				return s:find(arg_lead, 1, true) == 1
			end, subcommands)
		end,
	})
end

--- Open the code review interface
function M.open_review()
	local ReviewBuffer = require("oversight.buffers.review")
	ReviewBuffer.open()
end

--- Open the codebase browse interface
function M.open_browse()
	local BrowseBuffer = require("oversight.buffers.browse")
	BrowseBuffer.open()
end

--- Close any open review or browse buffers
function M.close()
	local ReviewBuffer = require("oversight.buffers.review")
	ReviewBuffer.close_all()
	local BrowseBuffer = require("oversight.buffers.browse")
	BrowseBuffer.close_all()
end

return M
