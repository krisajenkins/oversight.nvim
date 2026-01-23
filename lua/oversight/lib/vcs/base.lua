-- Base VCS backend class
-- Provides shared logic for all VCS backends (git, jj, etc.)

local logger = require("oversight.logger")
local Diff = require("oversight.lib.diff")

local M = {}

---Create a backend class with shared behavior.
---Returns a new class table that inherits from BackendClass via __index,
---without mutating the original.
---
---The returned class provides: new(), instance(), get_root(), get_ref(),
---get_branch(), has_changes(), get_file_diff(), get_all_diffs(),
---clear_cache(), get_head.
---
---The backend must implement:
---  .new(dir) → instance|nil  (sets self.type, self.root, self.ref, self.branch)
---  :refresh()                 (re-fetches ref and branch)
---  :get_changed_files()       (returns VcsFileChange[])
---  :get_file_diff_raw(path)   (returns raw diff string or nil)
---
---@param BackendClass table The backend class table (e.g. GitBackend or JjBackend)
---@return table Class A new class table augmented with shared methods
function M.create_backend(BackendClass)
	-- Create a new class that delegates to BackendClass for backend-specific methods
	local Class = setmetatable({}, { __index = BackendClass })
	Class.__index = Class

	-- Private per-backend singleton cache
	local instances = {}

	---Create a new backend instance with the correct metatable
	---@param dir string Directory
	---@return VcsBackend|nil backend Backend instance or nil
	function Class.new(dir)
		local backend = BackendClass.new(dir)
		if backend then
			setmetatable(backend, Class)
		end
		return backend
	end

	---Get or create backend instance for a directory
	---@param dir? string Directory (defaults to cwd)
	---@return VcsBackend|nil backend Backend instance or nil if not a valid repo
	function Class.instance(dir)
		dir = dir or vim.fn.getcwd()

		-- Resolve to absolute path
		dir = vim.fn.fnamemodify(dir, ":p")
		dir = dir:gsub("/$", "") -- Remove trailing slash

		if instances[dir] then
			return instances[dir]
		end

		local backend = Class.new(dir)
		if backend then
			instances[dir] = backend
		end
		return backend
	end

	---Get the repository root directory
	---@return string root Repository root
	function Class:get_root()
		return self.root
	end

	---Get the current reference (commit SHA or change ID)
	---@return string ref Current reference
	function Class:get_ref()
		return self.ref
	end

	---Get the current branch/bookmark name
	---@return string|nil branch Branch name or nil if detached
	function Class:get_branch()
		return self.branch
	end

	---Check if there are uncommitted changes
	---@return boolean has_changes True if there are changes
	function Class:has_changes()
		local files = self:get_changed_files()
		return #files > 0
	end

	---Get diff for a specific file
	---Uses get_file_diff_raw() (which the backend must implement) and handles
	---empty output, binary detection, and hunk parsing.
	---@param file_path string File path relative to repo root
	---@return FileDiff|nil diff File diff or nil on error
	function Class:get_file_diff(file_path)
		local raw = self:get_file_diff_raw(file_path)

		if raw == nil then
			logger.error("Failed to get diff for %s", file_path)
			return nil
		end

		if raw == "" then
			return {
				path = file_path,
				old_path = nil,
				status = "M",
				hunks = {},
				is_binary = false,
			}
		end

		-- Check for binary file
		if raw:match("\nBinary files [^\n]+ differ") or raw:match("^Binary files [^\n]+ differ") then
			return {
				path = file_path,
				old_path = nil,
				status = "M",
				hunks = {},
				is_binary = true,
			}
		end

		local lines = vim.split(raw, "\n")
		local hunks = Diff.parse_unified_diff(lines)

		return {
			path = file_path,
			old_path = nil,
			status = "M",
			hunks = hunks,
			is_binary = false,
		}
	end

	---Get all file diffs in the repository
	---@return FileDiff[] diffs List of file diffs
	function Class:get_all_diffs()
		local files = self:get_changed_files()
		local diffs = {}

		for _, file in ipairs(files) do
			local diff = self:get_file_diff(file.path)
			if diff then
				diff.status = file.status
				diff.old_path = file.old_path
				table.insert(diffs, diff)
			end
		end

		return diffs
	end

	---Clear cached backend instance
	---@param dir? string Directory to clear (clears all if nil)
	function Class.clear_cache(dir)
		if dir then
			instances[dir] = nil
		else
			instances = {}
		end
	end

	-- Backwards compatibility alias
	Class.get_head = Class.get_ref

	return Class
end

return M
