-- Jujutsu VCS backend implementation
-- Implements the VcsBackend interface for Jujutsu repositories

local logger = require("oversight.logger")
local base = require("oversight.lib.vcs.base")

---@class JjBackend : VcsBackend
---@field type "jj"
---@field root string Repository root directory
---@field ref string Current change ID
---@field branch string|nil Current bookmark(s)
local JjBackend = {}

---Get the jj CLI module
---@return table jj Jj CLI module
local function get_jj()
	return require("oversight.lib.vcs.jj.cli")
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

---Format a file path as a jj fileset literal (escaping glob characters)
---@param path string File path
---@return string fileset Path wrapped as file:"path" fileset
local function fileset_literal(path)
	-- Escape double quotes in the path, then wrap with file:"..."
	local escaped = path:gsub('"', '\\"')
	return 'file:"' .. escaped .. '"'
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

---Get list of changed files (working copy changes)
---@return VcsFileChange[] files List of changed files
function JjBackend:get_changed_files()
	local jj = get_jj()

	local result = jj.status():cwd(self.root):call()
	if not result.success then
		logger.error("Failed to get changed files: %s", result.stderr)
		return {}
	end

	return parse_jj_status(result.stdout)
end

---Get raw diff output for a specific file (for hashing/change detection)
---@param file_path string File path relative to repo root
---@return string|nil diff_raw Raw diff output or nil on error
function JjBackend:get_file_diff_raw(file_path)
	local jj = get_jj()
	-- Use file:"path" to treat path as literal, not a glob pattern
	local result = jj.diff():arg(fileset_literal(file_path)):cwd(self.root):call()
	if not result.success then
		return nil
	end
	return result.stdout
end

-- Apply shared backend methods (instance, get_root, get_ref, get_branch,
-- has_changes, get_file_diff, get_all_diffs, clear_cache, get_head)
base.create_backend(JjBackend)

-- Export internal function for testing (underscore prefix indicates testing-only export)
JjBackend._expand_rename_path = expand_rename_path

return JjBackend
