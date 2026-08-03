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
---
---`--git` is not optional. jj's default diff format is `color-words`, not
---unified, and the backend feeds this output straight to
---`Diff.parse_unified_diff` — which finds no `@@` headers in color-words output
---and returns zero hunks. Without the flag every file in a jj repository
---renders as an empty diff, unless the user happens to have set
---`ui.diff-formatter = ":git"` in their own jj config. Asking for the format we
---parse makes us independent of that.
---@return CliBuilder builder CLI builder
function M.diff()
	return jj():arg("diff"):flag("no-pager"):flag("git"):option("color", "never")
end

---Create a jj status builder
---@return CliBuilder builder CLI builder
function M.status()
	return jj():arg("status"):flag("no-pager"):option("color", "never")
end

---Create a jj file list builder
---@return CliBuilder builder CLI builder
function M.file_list()
	return jj():arg("file"):arg("list"):flag("no-pager")
end

---Create a raw jj builder
---@return CliBuilder builder CLI builder
function M.raw()
	return jj():flag("no-pager")
end

return M
