-- Storage module
-- Re-exports storage-related functionality

local M = {}

-- Lazy load submodules
function M.json()
	return require("oversight.lib.storage.json")
end

function M.session()
	return require("oversight.lib.storage.session")
end

return M
