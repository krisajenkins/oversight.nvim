-- Git integration module
-- Re-exports git-related functionality

local M = {}

-- Lazy load submodules
function M.cli()
	return require("oversight.lib.git.cli")
end

function M.repository()
	return require("oversight.lib.git.repository")
end

function M.diff()
	return require("oversight.lib.git.diff")
end

return M
