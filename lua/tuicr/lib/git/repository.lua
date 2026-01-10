local logger = require("tuicr.logger")

---@class GitRepository
---@field root string Repository root directory
---@field head string HEAD commit SHA
---@field branch string|nil Current branch name
local Repository = {}
Repository.__index = Repository

-- Singleton instances per directory
local instances = {}

---Get or create repository instance for a directory
---@param dir? string Directory (defaults to cwd)
---@return GitRepository|nil repo Repository instance or nil if not a git repo
function Repository.instance(dir)
	dir = dir or vim.fn.getcwd()

	-- Resolve to absolute path
	dir = vim.fn.fnamemodify(dir, ":p")
	dir = dir:gsub("/$", "") -- Remove trailing slash

	if instances[dir] then
		return instances[dir]
	end

	local repo = Repository.new(dir)
	if repo then
		instances[dir] = repo
	end
	return repo
end

---Create a new repository instance
---@param dir string Directory
---@return GitRepository|nil repo Repository instance or nil
function Repository.new(dir)
	local git = require("tuicr.lib.git.cli")

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
	local head = ""
	if head_result.success then
		head = vim.trim(head_result.stdout)
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
		root = root,
		head = head,
		branch = branch,
	}, Repository)

	return instance
end

---Get the repository root directory
---@return string root Repository root
function Repository:get_root()
	return self.root
end

---Get the HEAD commit SHA
---@return string head HEAD commit SHA
function Repository:get_head()
	return self.head
end

---Get the current branch name
---@return string|nil branch Branch name or nil if detached
function Repository:get_branch()
	return self.branch
end

---Refresh repository state (HEAD, branch)
function Repository:refresh()
	local git = require("tuicr.lib.git.cli")

	-- Refresh HEAD
	local head_result = git.rev_parse():arg("HEAD"):cwd(self.root):call()
	if head_result.success then
		self.head = vim.trim(head_result.stdout)
	end

	-- Refresh branch
	local branch_result = git.branch():flag("show-current"):cwd(self.root):call()
	if branch_result.success then
		local branch_name = vim.trim(branch_result.stdout)
		self.branch = branch_name ~= "" and branch_name or nil
	end
end

---@class GitFileChange
---@field status string Git status (A, M, D, R, C)
---@field path string File path
---@field old_path? string Original path for renamed files

---Get list of changed files (working tree vs HEAD)
---@return GitFileChange[] files List of changed files
function Repository:get_changed_files()
	local git = require("tuicr.lib.git.cli")

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

---Check if there are uncommitted changes
---@return boolean has_changes True if there are changes
function Repository:has_changes()
	local files = self:get_changed_files()
	return #files > 0
end

---Clear cached repository instance
---@param dir? string Directory to clear (clears all if nil)
function Repository.clear_cache(dir)
	if dir then
		instances[dir] = nil
	else
		instances = {}
	end
end

return Repository
