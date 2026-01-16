-- Tests for Git CLI and Repository modules

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Git CLI"] = MiniTest.new_set()

T["Git CLI"]["builds diff command"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.diff()

	-- Check that diff command is built correctly
	expect.equality(builder.cmd, "git")
	expect.equality(builder.args[1], "diff")
	expect.equality(builder.args[2], "--no-color")
end

T["Git CLI"]["builds status command"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.status()

	expect.equality(builder.cmd, "git")
	expect.equality(builder.args[1], "status")
end

T["Git CLI"]["builds rev-parse command"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.rev_parse()

	expect.equality(builder.cmd, "git")
	expect.equality(builder.args[1], "rev-parse")
end

T["Git CLI"]["arg() adds positional argument"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.raw():arg("status"):arg("--porcelain")

	expect.equality(builder.args[1], "status")
	expect.equality(builder.args[2], "--porcelain")
end

T["Git CLI"]["multiple arg() calls add arguments"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.raw():arg("log"):arg("-n"):arg("5")

	expect.equality(builder.args[1], "log")
	expect.equality(builder.args[2], "-n")
	expect.equality(builder.args[3], "5")
end

T["Git CLI"]["flag() adds flag with double dash"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.raw():arg("status"):flag("porcelain")

	expect.equality(builder.args[2], "--porcelain")
end

T["Git CLI"]["short_flag() adds flag with single dash"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.raw():arg("log"):short_flag("n")

	expect.equality(builder.args[2], "-n")
end

T["Git CLI"]["option() adds key-value option"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.raw():arg("log"):option("format", "%H")

	expect.equality(builder.args[2], "--format")
	expect.equality(builder.args[3], "%H")
end

T["Git CLI"]["cwd() sets working directory"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.raw():cwd("/tmp")

	expect.equality(builder.options.cwd, "/tmp")
end

T["Git CLI"]["chaining works correctly"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.diff():arg("HEAD"):flag("stat"):cwd("/tmp")

	expect.equality(builder.args[1], "diff")
	expect.equality(builder.args[2], "--no-color")
	expect.equality(builder.args[3], "HEAD")
	expect.equality(builder.args[4], "--stat")
	expect.equality(builder.options.cwd, "/tmp")
end

T["Git CLI"]["call() executes and returns result"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	-- Use rev-parse which should work in any git repo
	local result = git.rev_parse():flag("git-dir"):call()

	-- Type guarantees (result is GitResult with success, exit_code, stdout, stderr)
	-- are enforced by LuaCATS annotations in cli.lua
	expect.equality(result.success, true)
end

T["Git Repository"] = MiniTest.new_set()

T["Git Repository"]["instance() returns repository for current dir"] = function()
	local Repository = require("oversight.lib.vcs.git")

	-- Clear cache first
	Repository.clear_cache()

	local repo = Repository.instance()

	-- Type guarantees are enforced by LuaCATS annotations
	expect.equality(repo ~= nil, true)
end

T["Git Repository"]["get_root() returns repository root"] = function()
	local Repository = require("oversight.lib.vcs.git")
	Repository.clear_cache()

	local repo = Repository.instance()

	local root = repo:get_root()
	-- Root should be a valid directory
	expect.equality(vim.fn.isdirectory(root), 1)
	-- Root should contain .git
	expect.equality(vim.fn.isdirectory(root .. "/.git") + vim.fn.filereadable(root .. "/.git"), 1)
end

T["Git Repository"]["get_head() returns commit SHA"] = function()
	local Repository = require("oversight.lib.vcs.git")
	Repository.clear_cache()

	local repo = Repository.instance()

	local head = repo:get_head()
	-- HEAD should be a 40-character hex string
	expect.equality(#head, 40)
	expect.equality(head:match("^[0-9a-f]+$") ~= nil, true)
end

T["Git Repository"]["get_branch() returns branch name or nil"] = function()
	local Repository = require("oversight.lib.vcs.git")
	Repository.clear_cache()

	local repo = Repository.instance()

	local branch = repo:get_branch()
	-- Branch is either a string or nil (if detached HEAD)
	-- Type constraint (string|nil) enforced by LuaCATS annotations
	if branch ~= nil then
		expect.equality(#branch > 0, true)
	end
end

T["Git Repository"]["get_changed_files() returns table"] = function()
	local Repository = require("oversight.lib.vcs.git")
	Repository.clear_cache()

	local repo = Repository.instance()

	local files = repo:get_changed_files()

	-- Type guarantees (VcsFileChange[]) enforced by LuaCATS annotations
	-- Verify status values are valid VCS statuses
	for _, file in ipairs(files) do
		expect.equality(file.status:match("^[AMDRC]$") ~= nil, true)
		expect.equality(#file.path > 0, true)
	end
end

T["Git Repository"]["has_changes() returns boolean"] = function()
	local Repository = require("oversight.lib.vcs.git")
	Repository.clear_cache()

	local repo = Repository.instance()

	local has_changes = repo:has_changes()

	-- Type guarantee (boolean) enforced by LuaCATS annotations
	-- Just verify it returns without error - the boolean type is guaranteed
	expect.equality(has_changes == true or has_changes == false, true)
end

T["Git Repository"]["instance() caches repositories"] = function()
	local Repository = require("oversight.lib.vcs.git")
	Repository.clear_cache()

	local repo1 = Repository.instance()
	local repo2 = Repository.instance()

	-- Should return the same instance
	expect.equality(repo1, repo2)
end

T["Git Repository"]["clear_cache() removes cached instances"] = function()
	local Repository = require("oversight.lib.vcs.git")

	local repo1 = Repository.instance()
	Repository.clear_cache()
	local repo2 = Repository.instance()

	-- Should be different instances (by reference) after cache clear
	-- rawequal checks reference equality, not value equality
	expect.equality(rawequal(repo1, repo2), false)
end

T["Git Repository"]["refresh() updates head and branch"] = function()
	local Repository = require("oversight.lib.vcs.git")
	Repository.clear_cache()

	local repo = Repository.instance()
	local original_head = repo:get_head()

	-- Refresh should not error
	repo:refresh()

	-- Head should still be valid
	local refreshed_head = repo:get_head()
	expect.equality(#refreshed_head, 40)
	-- In a test environment, head shouldn't change
	expect.equality(original_head, refreshed_head)
end

return T
