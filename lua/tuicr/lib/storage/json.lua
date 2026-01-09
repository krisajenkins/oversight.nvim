-- JSON file I/O utilities for session persistence

local logger = require("tuicr.logger")

local M = {}

---Get the data directory for tuicr
---@return string path Data directory path
function M.get_data_dir()
	local xdg = os.getenv("XDG_DATA_HOME")
	if xdg and xdg ~= "" then
		return xdg .. "/tuicr"
	end
	return os.getenv("HOME") .. "/.local/share/tuicr"
end

---Ensure the data directory exists
---@return boolean success True if directory exists or was created
function M.ensure_data_dir()
	local data_dir = M.get_data_dir()
	if vim.fn.isdirectory(data_dir) == 0 then
		local ok = vim.fn.mkdir(data_dir, "p")
		if ok == 0 then
			logger.error("Failed to create data directory: %s", data_dir)
			return false
		end
	end
	return true
end

---Generate session file path for a repository
---@param repo_root string Repository root path
---@return string path Session file path
function M.session_path(repo_root)
	-- Create a unique hash from the repo path
	local hash = vim.fn.sha256(repo_root):sub(1, 16)
	return M.get_data_dir() .. "/" .. hash .. ".json"
end

---Read JSON from a file
---@param path string File path
---@return table|nil data Parsed JSON or nil on error
function M.read(path)
	if vim.fn.filereadable(path) == 0 then
		return nil
	end

	local ok, content = pcall(function()
		return vim.fn.readfile(path)
	end)

	if not ok or not content or #content == 0 then
		logger.error("Failed to read file: %s", path)
		return nil
	end

	local json_str = table.concat(content, "\n")

	local decode_ok, data = pcall(vim.json.decode, json_str)
	if not decode_ok then
		logger.error("Failed to parse JSON from %s: %s", path, tostring(data))
		return nil
	end

	return data
end

---Write JSON to a file
---@param path string File path
---@param data table Data to write
---@return boolean success True if write succeeded
function M.write(path, data)
	if not M.ensure_data_dir() then
		return false
	end

	local encode_ok, json_str = pcall(vim.json.encode, data)
	if not encode_ok then
		logger.error("Failed to encode JSON: %s", tostring(json_str))
		return false
	end

	-- Write as single line to avoid corrupting JSON with naive pretty-printing
	-- (String values containing {, [, etc. would be mangled by regex-based formatting)
	local lines = { json_str }

	local ok = pcall(function()
		vim.fn.writefile(lines, path)
	end)

	if not ok then
		logger.error("Failed to write file: %s", path)
		return false
	end

	return true
end

---Delete a session file
---@param path string File path
---@return boolean success True if deletion succeeded
function M.delete(path)
	if vim.fn.filereadable(path) == 0 then
		return true -- Already doesn't exist
	end

	local ok = pcall(function()
		vim.fn.delete(path)
	end)

	if not ok then
		logger.error("Failed to delete file: %s", path)
		return false
	end

	return true
end

---List all session files
---@return string[] paths List of session file paths
function M.list_sessions()
	local data_dir = M.get_data_dir()
	if vim.fn.isdirectory(data_dir) == 0 then
		return {}
	end

	local files = vim.fn.glob(data_dir .. "/*.json", false, true)
	return files
end

return M
