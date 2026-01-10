-- Health check module for tuicr
-- Run with :checkhealth tuicr

local M = {}

---Check if git is available and working
---@return boolean available True if git is available
local function check_git()
	local handle = io.popen("git --version 2>&1")
	if not handle then
		return false
	end
	local result = handle:read("*a")
	handle:close()
	return result:match("git version") ~= nil
end

---Check if we're in a git repository
---@return boolean in_repo True if in a git repository
local function check_git_repo()
	local handle = io.popen("git rev-parse --git-dir 2>&1")
	if not handle then
		return false
	end
	local result = handle:read("*a")
	handle:close()
	return not result:match("fatal:")
end

---Check if there are changes to review
---@return boolean has_changes True if there are uncommitted changes
local function check_has_changes()
	local handle = io.popen("git status --porcelain 2>&1")
	if not handle then
		return false
	end
	local result = handle:read("*a")
	handle:close()
	return result ~= ""
end

---Run health checks
function M.check()
	vim.health.start("tuicr")

	-- Check Neovim version
	if vim.fn.has("nvim-0.9.0") == 1 then
		vim.health.ok("Neovim version >= 0.9.0")
	else
		vim.health.error("Neovim >= 0.9.0 required", {
			"tuicr requires Neovim 0.9.0 or later",
			"Please upgrade your Neovim installation",
		})
	end

	-- Check git availability
	if check_git() then
		vim.health.ok("git is available")
	else
		vim.health.error("git not found", {
			"tuicr requires git to be installed and in PATH",
			"Install git from https://git-scm.com/",
		})
	end

	-- Check if in git repository (informational)
	if check_git_repo() then
		vim.health.ok("Current directory is a git repository")
	else
		vim.health.info("Current directory is not a git repository")
	end

	-- Check data directory
	local data_dir = vim.fn.stdpath("data") .. "/tuicr"
	if vim.fn.isdirectory(data_dir) == 1 then
		vim.health.ok("Data directory exists: " .. data_dir)
	else
		vim.health.info("Data directory will be created on first use: " .. data_dir)
	end
end

return M
