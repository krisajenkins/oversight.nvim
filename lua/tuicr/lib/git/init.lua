-- Git integration module
-- Re-exports git-related functionality

local M = {}

-- Lazy load submodules
function M.cli()
	return require("tuicr.lib.git.cli")
end

function M.repository()
	return require("tuicr.lib.git.repository")
end

function M.diff()
	return require("tuicr.lib.git.diff")
end

return M
