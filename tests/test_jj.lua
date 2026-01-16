-- Tests for JJ CLI and Backend modules

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["JJ CLI"] = MiniTest.new_set()

T["JJ CLI"]["builds root command"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.root()

	expect.equality(builder.cmd, "jj")
	expect.equality(builder.args[1], "root")
	expect.equality(builder.args[2], "--no-pager")
end

T["JJ CLI"]["builds status command with color=never"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.status()

	expect.equality(builder.cmd, "jj")
	expect.equality(builder.args[1], "status")
	expect.equality(builder.args[2], "--no-pager")
	expect.equality(builder.args[3], "--color")
	expect.equality(builder.args[4], "never")
end

T["JJ CLI"]["builds log command with color=never"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.log()

	expect.equality(builder.cmd, "jj")
	expect.equality(builder.args[1], "log")
	expect.equality(builder.args[2], "--no-pager")
	expect.equality(builder.args[3], "--no-graph")
	expect.equality(builder.args[4], "--color")
	expect.equality(builder.args[5], "never")
end

T["JJ CLI"]["builds diff command with color=never"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.diff()

	expect.equality(builder.cmd, "jj")
	expect.equality(builder.args[1], "diff")
	expect.equality(builder.args[2], "--no-pager")
	expect.equality(builder.args[3], "--color")
	expect.equality(builder.args[4], "never")
end

T["JJ CLI"]["arg() adds positional argument"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.raw():arg("status"):arg("--porcelain")

	expect.equality(builder.args[2], "status")
	expect.equality(builder.args[3], "--porcelain")
end

T["JJ CLI"]["flag() adds flag with double dash"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.raw():arg("status"):flag("no-pager")

	expect.equality(builder.args[3], "--no-pager")
end

T["JJ CLI"]["option() adds key-value option"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.raw():arg("log"):option("template", "change_id")

	expect.equality(builder.args[3], "--template")
	expect.equality(builder.args[4], "change_id")
end

T["JJ CLI"]["cwd() sets working directory"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.raw():cwd("/tmp")

	expect.equality(builder.options.cwd, "/tmp")
end

T["JJ Status Parsing"] = MiniTest.new_set()

-- We test status parsing by accessing the module's internal parsing
-- This requires a helper that exposes the parsing logic

T["JJ Status Parsing"]["parses modified files"] = function()
	-- Create a minimal test by using the backend on this repo (which is jj)
	local JjBackend = require("oversight.lib.vcs.jj")

	-- Check if we're in a jj repo
	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		-- Skip test if not in a jj repo
		return
	end

	JjBackend.clear_cache()
	local backend = JjBackend.instance()

	if backend then
		local files = backend:get_changed_files()
		expect.equality(type(files), "table")

		-- Each file should have status and path
		for _, file in ipairs(files) do
			expect.equality(type(file.status), "string")
			expect.equality(type(file.path), "string")
			-- Status should be one of M, A, D, R
			expect.equality(file.status:match("^[MADR]$") ~= nil, true)
		end
	end
end

T["JJ Status Parsing"]["has_changes returns boolean"] = function()
	local JjBackend = require("oversight.lib.vcs.jj")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	JjBackend.clear_cache()
	local backend = JjBackend.instance()

	if backend then
		local has_changes = backend:has_changes()
		expect.equality(type(has_changes), "boolean")
	end
end

T["JJ Rename Path Expansion"] = MiniTest.new_set()

-- Test the rename path expansion logic directly
-- We need to test various jj rename formats

T["JJ Rename Path Expansion"]["handles simple rename"] = function()
	-- We test by checking the backend parses renames correctly
	local JjBackend = require("oversight.lib.vcs.jj")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	JjBackend.clear_cache()
	local backend = JjBackend.instance()

	if backend then
		local files = backend:get_changed_files()

		-- Check that any renames have both path and old_path
		for _, file in ipairs(files) do
			if file.status == "R" then
				expect.equality(type(file.path), "string")
				expect.equality(type(file.old_path), "string")
				-- Paths should not contain braces
				expect.equality(file.path:match("{") == nil, true)
				expect.equality(file.old_path:match("{") == nil, true)
				-- Paths should not have double slashes
				expect.equality(file.path:match("//") == nil, true)
				expect.equality(file.old_path:match("//") == nil, true)
			end
		end
	end
end

T["JJ Rename Path Expansion"]["handles empty new part"] = function()
	-- Test case: lua/oversight/lib/{git => }/diff.lua
	-- Should expand to:
	--   old: lua/oversight/lib/git/diff.lua
	--   new: lua/oversight/lib/diff.lua (no double slash!)

	local JjBackend = require("oversight.lib.vcs.jj")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	JjBackend.clear_cache()
	local backend = JjBackend.instance()

	if backend then
		local files = backend:get_changed_files()

		-- Look for the specific rename of diff.lua
		for _, file in ipairs(files) do
			if file.status == "R" and file.path:match("diff%.lua$") then
				-- Should be lua/oversight/lib/diff.lua, not lua/oversight/lib//diff.lua
				expect.equality(file.path:match("//") == nil, true)
				-- The path should be valid
				expect.equality(file.path, "lua/oversight/lib/diff.lua")
				expect.equality(file.old_path, "lua/oversight/lib/git/diff.lua")
			end
		end
	end
end

T["JJ Rename Path Expansion"]["can get diff for renamed file"] = function()
	-- Test that get_file_diff works correctly for renamed files
	local JjBackend = require("oversight.lib.vcs.jj")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	JjBackend.clear_cache()
	local backend = JjBackend.instance()

	if backend then
		local files = backend:get_changed_files()

		-- Find a renamed file
		for _, file in ipairs(files) do
			if file.status == "R" then
				-- Get the diff for this renamed file
				local diff = backend:get_file_diff(file.path)

				expect.equality(diff ~= nil, true)
				if diff then
					-- Should NOT be marked as binary
					expect.equality(diff.is_binary, false)
					-- Should have hunks (assuming there are actual changes)
					expect.equality(type(diff.hunks), "table")
				end
				break -- Only test one renamed file
			end
		end
	end
end

T["JJ Fileset Literal Escaping"] = MiniTest.new_set()

-- Test the fileset_literal function by checking the output format
-- We access it indirectly through the backend behavior

T["JJ Fileset Literal Escaping"]["handles paths with brackets"] = function()
	-- Test that paths with glob characters like [] are handled correctly
	-- This is a regression test for the bug where paths like [year]/[month]/[slug].astro
	-- were interpreted as glob patterns instead of literal paths

	local JjBackend = require("oversight.lib.vcs.jj")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	JjBackend.clear_cache()
	local backend = JjBackend.instance()

	if backend then
		-- Test with a path that contains brackets
		-- Even if the file doesn't exist, we should get a valid (empty) result
		-- instead of a glob expansion error or unexpected match
		local diff = backend:get_file_diff("[nonexistent]/[test].lua")

		-- Should return a valid diff object (not nil from command failure)
		expect.equality(diff ~= nil, true)
		if diff then
			-- Should have empty hunks since file doesn't exist
			expect.equality(#diff.hunks, 0)
		end
	end
end

T["JJ Fileset Literal Escaping"]["handles paths with quotes"] = function()
	-- Test paths containing double quotes are properly escaped

	local JjBackend = require("oversight.lib.vcs.jj")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	JjBackend.clear_cache()
	local backend = JjBackend.instance()

	if backend then
		-- Test with a path containing a quote character
		local diff = backend:get_file_diff('file"with"quotes.lua')

		-- Should return a valid diff object, not fail due to quoting issues
		expect.equality(diff ~= nil, true)
	end
end

T["VCS Detection"] = MiniTest.new_set()

T["VCS Detection"]["detects jj repo"] = function()
	local Vcs = require("oversight.lib.vcs")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	Vcs.clear_cache()
	local backend = Vcs.instance()

	expect.equality(backend ~= nil, true)
	expect.equality(backend.type, "jj")
end

T["VCS Detection"]["jj backend has correct methods"] = function()
	local Vcs = require("oversight.lib.vcs")

	local cwd = vim.fn.getcwd()
	if vim.fn.isdirectory(cwd .. "/.jj") ~= 1 then
		return
	end

	Vcs.clear_cache()
	local backend = Vcs.instance()

	if backend and backend.type == "jj" then
		-- Check all required methods exist
		expect.equality(type(backend.get_root), "function")
		expect.equality(type(backend.get_ref), "function")
		expect.equality(type(backend.get_branch), "function")
		expect.equality(type(backend.get_changed_files), "function")
		expect.equality(type(backend.has_changes), "function")
		expect.equality(type(backend.get_file_diff), "function")
		expect.equality(type(backend.refresh), "function")
	end
end

return T
