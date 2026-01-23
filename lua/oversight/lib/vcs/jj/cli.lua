-- Jujutsu CLI command builder
-- Convenience constructors for jj commands

local Cli = require("oversight.lib.cli")

local M = {}

---Create a new jj builder
---@return CliBuilder builder CLI builder
local function jj()
	return Cli.new("jj")
end

---Create a jj root builder
---@return CliBuilder builder CLI builder
function M.root()
	return jj():arg("root"):flag("no-pager")
end

---Create a jj log builder
---@return CliBuilder builder CLI builder
function M.log()
	return jj():arg("log"):flag("no-pager"):flag("no-graph"):option("color", "never")
end

---Create a jj diff builder
---@return CliBuilder builder CLI builder
function M.diff()
	return jj():arg("diff"):flag("no-pager"):option("color", "never")
end

---Create a jj status builder
---@return CliBuilder builder CLI builder
function M.status()
	return jj():arg("status"):flag("no-pager"):option("color", "never")
end

---Create a raw jj builder
---@return CliBuilder builder CLI builder
function M.raw()
	return jj():flag("no-pager")
end

return M
