-- Health check module for oversight
-- Run with :checkhealth oversight

local Vcs = require("oversight.lib.vcs")

local M = {}

-- Minimum supported Neovim. Mirrors the Requirements section of the README and
-- vimdoc; keep the three in step.
local MIN_NVIM = { 0, 9, 0 }

-- Feature-detect the vim.health API. The start/ok/warn/error/info names are
-- Neovim 0.10+; 0.9 (which we claim to support) only has the report_* spellings,
-- so calling vim.health.start directly made :checkhealth fail on the oldest
-- version we advertise.
local health = vim.health
---@type table<string, fun(msg: string, advice?: string[])>
local h = {
	start = health.start or health.report_start,
	ok = health.ok or health.report_ok,
	warn = health.warn or health.report_warn,
	error = health.error or health.report_error,
	info = health.info or health.report_info,
}

---Locate a VCS binary and read its version.
---Uses exepath + a direct argv rather than `io.popen("... 2>&1")` so no shell is
---involved and we can report where the binary actually came from.
---@param cmd string Executable name ("git" or "jj")
---@return string? path Absolute path to the binary, or nil when not on PATH
---@return string? version Version string like "2.43.0", or nil if unparseable
local function probe(cmd)
	local path = vim.fn.exepath(cmd)
	if path == "" then
		return nil
	end

	local output = vim.fn.systemlist({ path, "--version" })
	for _, line in ipairs(output or {}) do
		local version = line:match("(%d+%.%d+%.%d+)")
		if version then
			return path, version
		end
	end

	return path
end

---Report on one VCS binary.
---@param cmd string Executable name
---@param label string Human-readable name
---@param missing_advice string[] Advice shown when the binary is absent
---@param missing_level "warn"|"info" How loudly to report absence
---@return boolean available
local function report_vcs(cmd, label, missing_advice, missing_level)
	local path, version = probe(cmd)
	if not path then
		h[missing_level](label .. " not found", missing_advice)
		return false
	end

	if version then
		h.ok(string.format("%s %s (%s)", label, version, path))
	else
		-- Present but unparseable output: still usable, just note it.
		h.warn(string.format("Found %s at %s but could not parse its version", label, path))
	end
	return true
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
	h.start("oversight")

	-- Check Neovim version
	local v = vim.version()
	local current = string.format("%d.%d.%d", v.major, v.minor, v.patch)
	local minimum = string.format("%d.%d.%d", MIN_NVIM[1], MIN_NVIM[2], MIN_NVIM[3])
	if vim.version.cmp({ v.major, v.minor, v.patch }, MIN_NVIM) < 0 then
		h.error(string.format("Neovim %s is older than the minimum supported %s", current, minimum), {
			"Please upgrade your Neovim installation",
		})
	else
		h.ok("Neovim " .. current)
	end

	-- Check VCS availability. No minimum version is asserted for either: we use
	-- only long-stable git subcommands, and picking a jj floor would be a guess.
	-- The discovered version is reported as a diagnostic instead.
	local git_available = report_vcs("git", "git", {
		"oversight supports git repositories",
		"Install git from https://git-scm.com/",
	}, "warn")

	local jj_available = report_vcs("jj", "jj (Jujutsu)", {
		"oversight also supports Jujutsu repositories",
		"Install jj from https://github.com/jj-vcs/jj",
	}, "info")

	-- Check if at least one VCS is available
	if not git_available and not jj_available then
		h.error("No supported VCS found", {
			"oversight requires either git or jj to be installed",
		})
	end

	-- Check current directory VCS
	local current_vcs = detect_current_vcs()
	if current_vcs then
		local vcs_name = Vcs.display_name(current_vcs)
		h.ok("Current directory is a " .. vcs_name .. " repository")
	else
		h.info("Current directory is not a version-controlled repository")
	end

	-- Check plenary, which lib/cli.lua depends on for every VCS invocation
	local missing = {}
	for _, mod in ipairs({ "plenary.job", "plenary.async" }) do
		if not pcall(require, mod) then
			table.insert(missing, mod)
		end
	end
	if #missing == 0 then
		h.ok("plenary.nvim is installed")
	else
		h.error("plenary.nvim is not available (missing: " .. table.concat(missing, ", ") .. ")", {
			"Install nvim-lua/plenary.nvim with your plugin manager",
		})
	end
end

return M
