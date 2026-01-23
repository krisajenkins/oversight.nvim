-- Git VCS backend implementation
-- Implements the VcsBackend interface for Git repositories

local logger = require("oversight.logger")
local base = require("oversight.lib.vcs.base")

---@class GitBackend : VcsBackend
---@field type "git"
---@field root string Repository root directory
---@field ref string HEAD commit SHA
---@field branch string|nil Current branch name
local GitBackend = {}

---Get the git CLI module
---@return table git Git CLI module
local function get_git()
	return require("oversight.lib.vcs.git.cli")
end

---Create a new backend instance
---@param dir string Directory
---@return GitBackend|nil backend Backend instance or nil
function GitBackend.new(dir)
	local git = get_git()

	-- Check if this is a git repository
	local result = git.rev_parse():flag("git-dir"):cwd(dir):call()
	if not result.success then
		logger.debug("Not a git repository: %s", dir)
		return nil
	end

	-- Get repository root
	local root_result = git.rev_parse():flag("show-toplevel"):cwd(dir):call()
	if not root_result.success then
		logger.error("Failed to get repository root: %s", root_result.stderr)
		return nil
	end
	local root = vim.trim(root_result.stdout)

	-- Get HEAD commit
	local head_result = git.rev_parse():arg("HEAD"):cwd(root):call()
	local ref = ""
	if head_result.success then
		ref = vim.trim(head_result.stdout)
	end

	-- Get current branch
	local branch_result = git.branch():flag("show-current"):cwd(root):call()
	local branch = nil
	if branch_result.success then
		local branch_name = vim.trim(branch_result.stdout)
		if branch_name ~= "" then
			branch = branch_name
		end
	end

	local instance = setmetatable({
		type = "git",
		root = root,
		ref = ref,
		branch = branch,
	}, GitBackend)

	return instance
end

---Refresh repository state (HEAD, branch)
function GitBackend:refresh()
	local git = get_git()

	-- Refresh HEAD
	local head_result = git.rev_parse():arg("HEAD"):cwd(self.root):call()
	if head_result.success then
		self.ref = vim.trim(head_result.stdout)
	end

	-- Refresh branch
	local branch_result = git.branch():flag("show-current"):cwd(self.root):call()
	if branch_result.success then
		local branch_name = vim.trim(branch_result.stdout)
		self.branch = branch_name ~= "" and branch_name or nil
	end
end

---Get list of changed files (working tree vs HEAD)
---@return VcsFileChange[] files List of changed files
function GitBackend:get_changed_files()
	local git = get_git()

	local result = git.diff():flag("name-status"):arg("HEAD"):cwd(self.root):call()
	if not result.success then
		logger.error("Failed to get changed files: %s", result.stderr)
		return {}
	end

	local files = {}
	for line in result.stdout:gmatch("[^\n]+") do
		local status, path = line:match("^(%S+)%s+(.+)$")
		if status and path then
			-- Handle renamed files (R100 old_path -> new_path)
			if status:match("^R") then
				local old_path, new_path = path:match("^(.+)%s+(.+)$")
				if old_path and new_path then
					table.insert(files, { status = "R", path = new_path, old_path = old_path })
				else
					table.insert(files, { status = "R", path = path })
				end
			else
				-- Normalize status to single character
				local normalized_status = status:sub(1, 1)
				table.insert(files, { status = normalized_status, path = path })
			end
		end
	end

	return files
end

---Get raw diff output for a specific file (for hashing/change detection)
---@param file_path string File path relative to repo root
---@return string|nil diff_raw Raw diff output or nil on error
function GitBackend:get_file_diff_raw(file_path)
	local git = get_git()
	local result = git.diff():arg("HEAD"):arg("--"):arg(file_path):cwd(self.root):call()
	if not result.success then
		return nil
	end
	return result.stdout
end

-- Create augmented class with shared backend methods (instance, get_root,
-- get_ref, get_branch, has_changes, get_file_diff, get_all_diffs,
-- clear_cache, get_head)
return base.create_backend(GitBackend)
