-- Storage module
-- Re-exports storage-related functionality

local M = {}

-- Lazy load submodules
function M.json()
	return require("tuicr.lib.storage.json")
end

function M.session()
	return require("tuicr.lib.storage.session")
end

return M
