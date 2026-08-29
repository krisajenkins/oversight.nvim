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
		-- `--name-status` separates its fields with TABs, so split on those
		-- rather than on whitespace: a path may legitimately contain spaces, and
		-- matching "^(.+)%s+(.+)$" against "R100\told name.md\tnew name.md"
		-- splits it at the wrong space and yields a pair of nonsense paths.
		local fields = vim.split(line, "\t", { plain = true })
		-- Statuses carry a similarity score for renames and copies (R100, C75);
		-- the first letter is the part we model.
		local status = fields[1] and fields[1]:sub(1, 1)

		if status == "R" or status == "C" then
			-- Two paths: the source and the destination.
			if fields[2] and fields[3] then
				table.insert(files, { status = status, path = fields[3], old_path = fields[2] })
			elseif fields[2] then
				table.insert(files, { status = status, path = fields[2] })
			end
		elseif status and fields[2] then
			table.insert(files, { status = status, path = fields[2] })
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

---Read a file's contents as they are at the base revision (HEAD).
---
---Not a diff: the native diff view is handed two whole files and lets Neovim
---work out what moved. Renames pass their `old_path`, because that is the name
---the content had at HEAD.
---@param file_path string File path relative to repo root, as it was at HEAD
---@return string[]|nil lines File lines, {} when the path is not in HEAD at all
---(a newly added file), nil on error
function GitBackend:get_file_at_base(file_path)
	local git = get_git()
	local result = git.show():arg("HEAD:" .. file_path):cwd(self.root):call()

	-- git spells "not at this revision" two ways depending on whether the path
	-- exists in the working copy, and both are a normal answer here rather than a
	-- failure: an added file simply has no content at HEAD.
	local absent = not result.success
		and (
			result.stderr:find("does not exist in", 1, true) ~= nil
			or result.stderr:find("exists on disk, but not in", 1, true) ~= nil
		)

	if not result.success and not absent then
		logger.error("Failed to read %s at HEAD: %s", file_path, result.stderr)
	end

	return base.file_content_lines(result, absent)
end

---Get list of all tracked files in the repository
---@return VcsFileChange[] files List of tracked files (status is empty string)
function GitBackend:get_tracked_files()
	local git = get_git()

	local result = git.ls_files():cwd(self.root):call()
	if not result.success then
		logger.error("Failed to list tracked files: %s", result.stderr)
		return {}
	end

	local files = {}
	for line in result.stdout:gmatch("[^\n]+") do
		local path = vim.trim(line)
		if path ~= "" then
			table.insert(files, { status = "", path = path })
		end
	end

	return files
end

-- Create augmented class with shared backend methods (instance, get_root,
-- get_ref, get_branch, has_changes, read_file, clear_cache, get_head)
return base.create_backend(GitBackend)
