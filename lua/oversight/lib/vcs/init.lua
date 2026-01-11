-- VCS abstraction layer
-- Provides a unified interface for version control systems

local logger = require("oversight.logger")

local M = {}

---@class VcsFileChange
---@field status string VCS status (A, M, D, R, C)
---@field path string File path
---@field old_path? string Original path for renamed files

---@class VcsBackend
---@field type "git"|"jj" VCS type identifier
---@field root string Repository root directory
---@field ref string Current commit/change reference
---@field branch string|nil Current branch name

-- Lazy-loaded backend modules
local backends = {
	jj = function()
		return require("oversight.lib.vcs.jj")
	end,
	git = function()
		return require("oversight.lib.vcs.git")
	end,
}

---Detect which VCS is in use for a directory
---Walks up the directory tree until a VCS is found
---@param dir string Directory to check
---@return table|nil backend Backend module or nil
---@return string|nil root Repository root or nil
local function detect_vcs(dir)
	local current = dir

	while current and current ~= "" and current ~= "/" do
		-- Check for jj first (jj repos also have .git)
		if vim.fn.isdirectory(current .. "/.jj") == 1 then
			logger.debug("Detected jj repository at: %s", current)
			return backends.jj(), current
		end

		-- Check for git
		if vim.fn.isdirectory(current .. "/.git") == 1 then
			logger.debug("Detected git repository at: %s", current)
			return backends.git(), current
		end

		-- Check for .git file (worktrees, submodules)
		if vim.fn.filereadable(current .. "/.git") == 1 then
			logger.debug("Detected git worktree/submodule at: %s", current)
			return backends.git(), current
		end

		-- Move to parent directory
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			break
		end
		current = parent
	end

	return nil, nil
end

---Get or create a VCS backend instance for a directory
---@param dir? string Directory (defaults to cwd)
---@return VcsBackend|nil backend Backend instance or nil if not a VCS repo
function M.instance(dir)
	dir = dir or vim.fn.getcwd()

	-- Resolve to absolute path
	dir = vim.fn.fnamemodify(dir, ":p")
	dir = dir:gsub("/$", "") -- Remove trailing slash

	local Backend = detect_vcs(dir)
	if not Backend then
		logger.debug("No VCS detected for: %s", dir)
		return nil
	end

	return Backend.instance(dir)
end

---Create a fresh VCS backend instance (no caching)
---@param dir string Directory
---@return VcsBackend|nil backend Backend instance or nil
function M.new(dir)
	dir = vim.fn.fnamemodify(dir, ":p")
	dir = dir:gsub("/$", "")

	local Backend = detect_vcs(dir)
	if not Backend then
		return nil
	end

	return Backend.new(dir)
end

---Clear cached instances
---@param dir? string Directory to clear (clears all if nil)
function M.clear_cache(dir)
	-- Clear from both backends
	local git = require("oversight.lib.vcs.git")
	local ok_jj, jj = pcall(require, "oversight.lib.vcs.jj")

	git.clear_cache(dir)
	if ok_jj then
		jj.clear_cache(dir)
	end
end

---Check if a VCS tool is available
---@param vcs_type "git"|"jj" VCS type to check
---@return boolean available True if the tool is installed
function M.is_available(vcs_type)
	if vcs_type == "git" then
		return vim.fn.executable("git") == 1
	elseif vcs_type == "jj" then
		return vim.fn.executable("jj") == 1
	end
	return false
end

---Get display name for a VCS type
---@param vcs_type "git"|"jj" VCS type
---@return string name Human-readable name
function M.display_name(vcs_type)
	if vcs_type == "git" then
		return "Git"
	elseif vcs_type == "jj" then
		return "Jujutsu"
	end
	return vcs_type
end

return M
