-- Health check module for oversight
-- Run with :checkhealth oversight

local Vcs = require("oversight.lib.vcs")

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

---Check if jj is available and working
---@return boolean available True if jj is available
local function check_jj()
	local handle = io.popen("jj --version 2>&1")
	if not handle then
		return false
	end
	local result = handle:read("*a")
	handle:close()
	return result:match("jj") ~= nil
end

---Check what VCS the current directory uses
---@return "git"|"jj"|nil vcs_type VCS type or nil if not in a repo
local function detect_current_vcs()
	local cwd = vim.fn.getcwd()

	-- Check for jj first (jj repos also have .git)
	local current = cwd
	while current and current ~= "" and current ~= "/" do
		if vim.fn.isdirectory(current .. "/.jj") == 1 then
			return "jj"
		end
		if vim.fn.isdirectory(current .. "/.git") == 1 then
			return "git"
		end
		if vim.fn.filereadable(current .. "/.git") == 1 then
			return "git"
		end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then
			break
		end
		current = parent
	end

	return nil
end

---Run health checks
function M.check()
	vim.health.start("oversight")

	-- Check Neovim version
	if vim.fn.has("nvim-0.9.0") == 1 then
		vim.health.ok("Neovim version >= 0.9.0")
	else
		vim.health.error("Neovim >= 0.9.0 required", {
			"oversight requires Neovim 0.9.0 or later",
			"Please upgrade your Neovim installation",
		})
	end

	-- Check git availability
	local git_available = check_git()
	if git_available then
		vim.health.ok("git is available")
	else
		vim.health.warn("git not found", {
			"oversight supports git repositories",
			"Install git from https://git-scm.com/",
		})
	end

	-- Check jj availability
	local jj_available = check_jj()
	if jj_available then
		vim.health.ok("jj (Jujutsu) is available")
	else
		vim.health.info("jj (Jujutsu) not found", {
			"oversight also supports Jujutsu repositories",
			"Install jj from https://github.com/martinvonz/jj",
		})
	end

	-- Check if at least one VCS is available
	if not git_available and not jj_available then
		vim.health.error("No supported VCS found", {
			"oversight requires either git or jj to be installed",
		})
	end

	-- Check current directory VCS
	local current_vcs = detect_current_vcs()
	if current_vcs then
		local vcs_name = Vcs.display_name(current_vcs)
		vim.health.ok("Current directory is a " .. vcs_name .. " repository")
	else
		vim.health.info("Current directory is not a version-controlled repository")
	end

	-- Check data directory
	local data_dir = vim.fn.stdpath("data") .. "/oversight"
	if vim.fn.isdirectory(data_dir) == 1 then
		vim.health.ok("Data directory exists: " .. data_dir)
	else
		vim.health.info("Data directory will be created on first use: " .. data_dir)
	end
end

return M
