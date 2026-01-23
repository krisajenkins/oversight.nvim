-- Git CLI command builder
-- Convenience constructors for git commands

local Cli = require("oversight.lib.cli")

local M = {}

---Create a new git builder
---@return CliBuilder builder CLI builder
local function git()
	return Cli.new("git")
end

---Create a git diff builder
---@return CliBuilder builder CLI builder
function M.diff()
	return git():arg("diff"):flag("no-color")
end

---Create a git status builder
---@return CliBuilder builder CLI builder
function M.status()
	return git():arg("status")
end

---Create a git show builder
---@return CliBuilder builder CLI builder
function M.show()
	return git():arg("show"):flag("no-color")
end

---Create a git log builder
---@return CliBuilder builder CLI builder
function M.log()
	return git():arg("log")
end

---Create a git rev-parse builder
---@return CliBuilder builder CLI builder
function M.rev_parse()
	return git():arg("rev-parse")
end

---Create a git branch builder
---@return CliBuilder builder CLI builder
function M.branch()
	return git():arg("branch")
end

---Create a raw git builder
---@return CliBuilder builder CLI builder
function M.raw()
	return git()
end

return M
