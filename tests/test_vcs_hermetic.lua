-- The one place a real VCS binary runs.
--
-- Everything else in the suite talks to tests/helpers/mock_cli.lua replaying
-- frozen captures. That is fast and deterministic, but it can only ever prove
-- that the parsers handle the bytes we recorded — not that git and jj still
-- produce those bytes. This file closes that loop: it builds a throwaway
-- repository in a temp directory, runs the real backend against it, and checks
-- the results agree with what the fixtures describe.
--
-- Both repositories are built with a neutral tool configuration (no global git
-- config, a purpose-written JJ_CONFIG). That is not tidiness: the plugin
-- inherits this process's environment, so without it the developer's own
-- settings leak into the assertions. `ui.diff-formatter = ":git"` in a personal
-- jj config is exactly what hid the missing `--git` flag for as long as it was
-- missing.

local T = MiniTest.new_set()
local expect = MiniTest.expect

-- These tests must talk to the real CLI, so drop anything a previously-run test
-- file left swapped into package.loaded.
local function use_real_cli()
	package.loaded["oversight.lib.cli"] = nil
	package.loaded["oversight.lib.vcs.git.cli"] = nil
	package.loaded["oversight.lib.vcs.jj.cli"] = nil
	require("oversight.lib.vcs").clear_cache()
end

---Run a shell script, failing the test with its output if it errors.
---@param cwd string
---@param script string
local function sh(cwd, script)
	local out = vim.fn.system({ "bash", "-euo", "pipefail", "-c", "cd " .. vim.fn.shellescape(cwd) .. "\n" .. script })
	if vim.v.shell_error ~= 0 then
		error(string.format("setup command failed (exit %d):\n%s", vim.v.shell_error, out))
	end
end

---Set an environment variable, returning a function that restores it.
---@param name string
---@param value string
---@return fun()
local function push_env(name, value)
	local previous = vim.fn.getenv(name)
	vim.fn.setenv(name, value)
	return function()
		-- getenv yields vim.NIL for an unset variable, which setenv accepts back
		-- as "unset it again".
		vim.fn.setenv(name, previous)
	end
end

-- The committed state, then the working-copy changes on top. Deliberately
-- smaller than the fixture demo repo: this test proves the shape of real output
-- still parses, not every edge case.
local SEED = [[
mkdir -p src
printf 'one\ntwo\nthree\n' > src/kept.lua
printf 'alpha\nbeta\n' > src/edited.lua
printf 'to be removed\n' > src/removed.lua
printf 'original\n' > src/renamed_from.lua
]]

local CHANGES = [[
printf 'alpha\nBETA\n' > src/edited.lua
printf 'brand new\n' > src/added.lua
rm src/removed.lua
mv src/renamed_from.lua src/renamed_to.lua
]]

---@param files VcsFileChange[]
---@return table<string, string> by_path Path to status
local function status_by_path(files)
	local map = {}
	for _, file in ipairs(files) do
		map[file.path] = file.status
	end
	return map
end

-- ---------------------------------------------------------------------------
-- git
-- ---------------------------------------------------------------------------

T["git, for real"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			use_real_cli()
		end,
	},
})

---Build a throwaway git repository and return its resolved root.
---@return string root
---@return fun() cleanup
local function make_git_repo()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")

	-- Neutralise the developer's own git configuration for the duration.
	local restore_global = push_env("GIT_CONFIG_GLOBAL", "/dev/null")
	local restore_system = push_env("GIT_CONFIG_SYSTEM", "/dev/null")

	sh(dir, [[
export GIT_AUTHOR_NAME='Hermetic Test' GIT_AUTHOR_EMAIL='test@example.com'
export GIT_COMMITTER_NAME='Hermetic Test' GIT_COMMITTER_EMAIL='test@example.com'
git init --quiet --initial-branch=main
]] .. SEED .. [[
git add -A
git commit --quiet -m 'Initial commit'
]] .. CHANGES .. [[
git add -A
]])

	-- git reports its own resolved root; on macOS the temp path is a symlink.
	local root = vim.fn.resolve(dir)
	return root, function()
		restore_global()
		restore_system()
		vim.fn.delete(dir, "rf")
	end
end

T["git, for real"]["parses a real repository the way the fixtures say"] = function()
	local root, cleanup = make_git_repo()
	local ok, err = pcall(function()
		local backend = require("oversight.lib.vcs").instance(root)
		if not backend then
			error("expected a git backend for " .. root)
		end

		expect.equality(backend.type, "git")
		expect.equality(backend:get_root(), root)
		expect.equality(backend:get_branch(), "main")
		expect.equality(#backend:get_ref(), 40)

		expect.equality(status_by_path(backend:get_changed_files()), {
			["src/added.lua"] = "A",
			["src/edited.lua"] = "M",
			["src/removed.lua"] = "D",
			["src/renamed_to.lua"] = "R",
		})

		-- The diff view is handed whole files, so this is what has to be right:
		-- the content at the base revision, split into lines the same way
		-- `readfile` splits the working copy.
		expect.equality(backend:get_file_at_base("src/edited.lua"), { "alpha", "beta" })
		expect.equality(backend:read_file("src/edited.lua"), { "alpha", "BETA" })

		-- A file that only exists in the working copy has no content at the base.
		-- That is an empty file, not a failure.
		expect.equality(backend:get_file_at_base("src/added.lua"), {})

		-- A rename is read under its old name; the new one is not at HEAD.
		expect.equality(backend:get_file_at_base("src/renamed_from.lua"), { "original" })
	end)

	cleanup()
	if not ok then
		error(err)
	end
end

-- ---------------------------------------------------------------------------
-- jj
-- ---------------------------------------------------------------------------

T["jj, for real"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			use_real_cli()
		end,
	},
})

---@return string root
---@return fun() cleanup
local function make_jj_repo()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")

	-- A config with an identity and nothing else. In particular no
	-- ui.diff-formatter, so `jj diff` falls back to its default format and the
	-- backend has to ask for the one it can parse.
	local config = dir .. "/jj-config.toml"
	vim.fn.writefile({ "[user]", 'name = "Hermetic Test"', 'email = "test@example.com"' }, config)
	local restore_config = push_env("JJ_CONFIG", config)

	local repo = dir .. "/repo"
	vim.fn.mkdir(repo, "p")
	sh(repo, [[
jj git init . > /dev/null
]] .. SEED .. [[
jj commit --quiet -m 'Initial commit'
]] .. CHANGES)

	return vim.fn.resolve(repo), function()
		restore_config()
		vim.fn.delete(dir, "rf")
	end
end

T["jj, for real"]["parses a real repository the way the fixtures say"] = function()
	if vim.fn.executable("jj") ~= 1 then
		MiniTest.skip("jj is not on PATH")
	end

	local root, cleanup = make_jj_repo()
	local ok, err = pcall(function()
		local backend = require("oversight.lib.vcs").instance(root)
		if not backend then
			error("expected a jj backend for " .. root)
		end

		expect.equality(backend.type, "jj")
		expect.equality(backend:get_root(), root)
		expect.equality(#backend:get_ref(), 32)

		expect.equality(status_by_path(backend:get_changed_files()), {
			["src/added.lua"] = "A",
			["src/edited.lua"] = "M",
			["src/removed.lua"] = "D",
			["src/renamed_to.lua"] = "R",
		})

		expect.equality(backend:get_file_at_base("src/edited.lua"), { "alpha", "beta" })
		expect.equality(backend:read_file("src/edited.lua"), { "alpha", "BETA" })

		expect.equality(backend:get_file_at_base("src/added.lua"), {})
		expect.equality(backend:get_file_at_base("src/renamed_from.lua"), { "original" })

		-- `jj diff` still runs, for the hash that tells a review its file moved
		-- underneath it. jj's default diff format is color-words, which carries
		-- no `@@` header at all — so this is what catches a missing `--git`.
		local raw = backend:get_file_diff_raw("src/edited.lua")
		expect.equality(type(raw), "string")
		expect.equality(raw:find("@@", 1, true) ~= nil, true)
	end)

	cleanup()
	if not ok then
		error(err)
	end
end

return T
