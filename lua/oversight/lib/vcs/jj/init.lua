-- Jujutsu VCS backend implementation
-- Implements the VcsBackend interface for Jujutsu repositories

local logger = require("oversight.logger")
local Diff = require("oversight.lib.diff")

---@class JjBackend : VcsBackend
---@field type "jj"
---@field root string Repository root directory
---@field ref string Current change ID
---@field branch string|nil Current bookmark(s)
local JjBackend = {}
JjBackend.__index = JjBackend

-- Singleton instances per directory
local instances = {}

---Get the jj CLI module
---@return table jj Jj CLI module
local function get_jj()
	return require("oversight.lib.vcs.jj.cli")
end

---Get or create backend instance for a directory
---@param dir? string Directory (defaults to cwd)
---@return JjBackend|nil backend Backend instance or nil if not a jj repo
function JjBackend.instance(dir)
	dir = dir or vim.fn.getcwd()

	-- Resolve to absolute path
	dir = vim.fn.fnamemodify(dir, ":p")
	dir = dir:gsub("/$", "") -- Remove trailing slash

	if instances[dir] then
		return instances[dir]
	end

	local backend = JjBackend.new(dir)
	if backend then
		instances[dir] = backend
	end
	return backend
end

---Create a new backend instance
---@param dir string Directory
---@return JjBackend|nil backend Backend instance or nil
function JjBackend.new(dir)
	local jj = get_jj()

	-- Get repository root (also validates this is a jj repo)
	local root_result = jj.root():cwd(dir):call()
	if not root_result.success then
		logger.debug("Not a jj repository: %s", dir)
		return nil
	end
	local root = vim.trim(root_result.stdout)

	-- Get current change ID (@ is the working copy)
	local ref_result =
		jj.log():option("revisions", "@"):option("template", "change_id"):option("limit", "1"):cwd(root):call()
	local ref = ""
	if ref_result.success then
		ref = vim.trim(ref_result.stdout)
	end

	-- Get current bookmarks
	local branch_result =
		jj.log():option("revisions", "@"):option("template", "bookmarks"):option("limit", "1"):cwd(root):call()
	local branch = nil
	if branch_result.success then
		local branch_str = vim.trim(branch_result.stdout)
		if branch_str ~= "" then
			branch = branch_str
		end
	end

	local instance = setmetatable({
		type = "jj",
		root = root,
		ref = ref,
		branch = branch,
	}, JjBackend)

	return instance
end

---Get the repository root directory
---@return string root Repository root
function JjBackend:get_root()
	return self.root
end

---Get the current reference (change ID)
---@return string ref Current change ID
function JjBackend:get_ref()
	return self.ref
end

---Get the current bookmark name(s)
---@return string|nil branch Bookmark name(s) or nil
function JjBackend:get_branch()
	return self.branch
end

---Refresh repository state
function JjBackend:refresh()
	local jj = get_jj()

	-- Refresh change ID
	local ref_result =
		jj.log():option("revisions", "@"):option("template", "change_id"):option("limit", "1"):cwd(self.root):call()
	if ref_result.success then
		self.ref = vim.trim(ref_result.stdout)
	end

	-- Refresh bookmarks
	local branch_result =
		jj.log():option("revisions", "@"):option("template", "bookmarks"):option("limit", "1"):cwd(self.root):call()
	if branch_result.success then
		local branch_str = vim.trim(branch_result.stdout)
		self.branch = branch_str ~= "" and branch_str or nil
	end
end

---Expand jj rename path with {old => new} substitution
---Example: "path/to/{old => new}/file.lua" returns "path/to/old/file.lua", "path/to/new/file.lua"
---Example: "path/to/{old => }/file.lua" returns "path/to/old/file.lua", "path/to/file.lua"
---@param path string Path with {old => new} pattern
---@return string old_path, string new_path
local function expand_rename_path(path)
	-- Find the {old => new} part
	local prefix, old_part, new_part, suffix = path:match("^(.-)%{(.-)%s*=>%s*(.-)%}(.*)$")
	if prefix and old_part and suffix then
		-- Handle empty parts by not adding extra slashes
		local old_path, new_path

		if old_part == "" then
			old_path = prefix .. suffix
		else
			old_path = prefix .. old_part .. suffix
		end

		if new_part == "" then
			new_path = prefix .. suffix
		else
			new_path = prefix .. new_part .. suffix
		end

		-- Clean up any double slashes that might occur
		old_path = old_path:gsub("//+", "/")
		new_path = new_path:gsub("//+", "/")

		return old_path, new_path
	end
	-- No substitution pattern found, return path as-is
	return path, path
end

---Parse jj status output to get changed files
---@param status_output string Status command output
---@return VcsFileChange[] files List of changed files
local function parse_jj_status(status_output)
	local files = {}

	for line in status_output:gmatch("[^\n]+") do
		-- Skip header line "Working copy changes:"
		-- Skip footer lines starting with "Working copy" or "Parent commit"
		if not line:match("^Working copy") and not line:match("^Parent commit") then
			-- jj status format: "M path/to/file" or "A path/to/file" etc.
			-- Renames: "R path/to/{old => new}/file.lua"
			local status, path = line:match("^([MADR])%s+(.+)$")

			if status and path then
				if status == "R" then
					-- Handle renames with {old => new} substitution
					local old_path, new_path = expand_rename_path(path)
					table.insert(files, { status = "R", path = new_path, old_path = old_path })
				else
					table.insert(files, { status = status, path = path })
				end
			end
		end
	end

	return files
end

---Get list of changed files (working copy changes)
---@return VcsFileChange[] files List of changed files
function JjBackend:get_changed_files()
	local jj = get_jj()

	-- Use jj diff --stat to get changed files, or parse jj status
	-- jj status gives us file status directly
	local result = jj.status():cwd(self.root):call()
	if not result.success then
		logger.error("Failed to get changed files: %s", result.stderr)
		return {}
	end

	return parse_jj_status(result.stdout)
end

---Check if there are uncommitted changes
---@return boolean has_changes True if there are changes
function JjBackend:has_changes()
	local files = self:get_changed_files()
	return #files > 0
end

---Get diff for a specific file
---@param file_path string File path relative to repo root
---@return FileDiff|nil diff File diff or nil on error
function JjBackend:get_file_diff(file_path)
	local jj = get_jj()

	-- jj diff outputs unified diff format
	local result = jj.diff():arg(file_path):cwd(self.root):call()

	if not result.success then
		logger.error("Failed to get diff for %s: %s", file_path, result.stderr)
		return nil
	end

	if result.stdout == "" then
		-- No changes for this file
		return {
			path = file_path,
			old_path = nil,
			status = "M",
			hunks = {},
			is_binary = false,
		}
	end

	-- Check for binary file
	-- Match the actual binary file message format: "Binary files ... and ... differ"
	-- Be specific to avoid matching code that contains "Binary files" as a string
	if result.stdout:match("\nBinary files [^\n]+ differ") or result.stdout:match("^Binary files [^\n]+ differ") then
		return {
			path = file_path,
			old_path = nil,
			status = "M",
			hunks = {},
			is_binary = true,
		}
	end

	local lines = vim.split(result.stdout, "\n")
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
function JjBackend:get_all_diffs()
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
function JjBackend.clear_cache(dir)
	if dir then
		instances[dir] = nil
	else
		instances = {}
	end
end

-- Alias for consistency with git backend
JjBackend.get_head = JjBackend.get_ref

return JjBackend
