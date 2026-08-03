-- A fixture-backed stand-in for `oversight.lib.cli`.
--
-- Both VCS backends build their commands on the one low-level builder, so a
-- single mock at that level covers git and jj alike. Installing it lets a test
-- exercise the real backend parsing code against frozen captures of real tool
-- output (tests/fixtures/) instead of against whatever this working copy
-- happens to contain today.
--
--     local MockCli = require("tests.helpers.mock_cli")
--     MockCli.install()          -- in pre_case
--     MockCli.uninstall()        -- in post_case, alongside assert_no_misses()
--
-- The default routes describe the demo repository that
-- scripts/generate-fixtures.sh builds; see tests/fixtures/README.md for its
-- shape. Tests that need something else override a route with `MockCli.set`.

local MockCli = {}

---Where the mock claims the repository lives. Not a real directory: nothing in
---the fixture-backed tests touches the filesystem. Override with `set_root` for
---tests that do (Backend:read_file reads from disk, not from the CLI).
MockCli.root = "/tmp/oversight-mock-repo"

---Every command the mock was asked to run, most recent last. Each entry is
---{ cmd, args, cwd, cmdline }. Assert against `cmdline` to pin down the exact
---flags a backend passes — that is the only place some of them are visible.
---@type table[]
MockCli.calls = {}

---Command lines that matched no route. See `assert_no_misses`.
---@type string[]
MockCli.misses = {}

---@type table[] Active routes, most recently added first.
MockCli.routes = {}

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- Resolve fixtures relative to this file rather than to the working directory,
-- so the mock keeps working if a test runner ever chdirs.
local HELPERS_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*)/[^/]*$")
local FIXTURE_DIR = HELPERS_DIR .. "/../fixtures"

---Read a fixture verbatim.
---
---The captures are byte-exact tool output, so they must be handed back the way
---the real `call()` hands back stdout: joined with "\n" and *without* a
---trailing newline, which is what `table.concat(job:result(), "\n")` produces.
---@param name string Path under tests/fixtures, e.g. "git-outputs/ls-files.txt"
---@return string contents
function MockCli.fixture(name)
	local path = FIXTURE_DIR .. "/" .. name
	local fd = io.open(path, "r")
	if not fd then
		error(string.format("mock_cli: no such fixture: %s (looked in %s)", name, path))
	end
	local contents = fd:read("*a")
	fd:close()
	return (contents:gsub("\n$", ""))
end

-- ---------------------------------------------------------------------------
-- Routing
-- ---------------------------------------------------------------------------

---Route a command to a response.
---
---Matching is on a plain substring of the full command line ("git diff
-----no-color --name-status HEAD"), not a Lua pattern — VCS command lines are
---full of `-` and `--`, which would need escaping in every single route.
---
---Later calls take precedence, so a test can override a default route without
---clearing the rest.
---@param contains string Substring that identifies the command
---@param response table { fixture = string } or { stdout = string } or a full CliResult
function MockCli.set(contains, response)
	table.insert(MockCli.routes, 1, { contains = contains, response = response })
end

---Make a matching command fail, the way a real one does.
---@param contains string Substring that identifies the command
---@param stderr string Error message
---@param exit_code? number Exit code (default 1)
function MockCli.set_failure(contains, stderr, exit_code)
	MockCli.set(contains, {
		success = false,
		exit_code = exit_code or 1,
		stdout = "",
		stderr = stderr,
	})
end

---Restore the default routes and forget all recorded calls and misses.
function MockCli.reset()
	MockCli.calls = {}
	MockCli.misses = {}
	MockCli.routes = {}
	MockCli.root = "/tmp/oversight-mock-repo"
	MockCli.install_default_routes()
end

---Point the mock at a real directory, for tests that also read files from disk.
---@param dir string
function MockCli.set_root(dir)
	MockCli.root = dir
end

---Fail the current test if any command went unrouted.
---
---`call()` deliberately returns a failure *result* on a miss rather than
---raising (see below), which keeps the plugin's own error handling in play but
---means a miss can otherwise show up as a confusing empty list three layers
---away. Call this in post_case to name the command instead.
function MockCli.assert_no_misses()
	if #MockCli.misses == 0 then
		return
	end
	error("mock_cli: unrouted commands:\n  " .. table.concat(MockCli.misses, "\n  "))
end

---The routes describing the generated demo repository.
function MockCli.install_default_routes()
	-- Added last-first, so declare these in order of increasing specificity:
	-- `set` prepends, and the first match wins.
	local defaults = {
		-- git: repository identity
		{ "git rev-parse --git-dir", { stdout = ".git" } },
		{ "git rev-parse --show-toplevel", {
			stdout = function()
				return MockCli.root
			end,
		} },
		{ "git rev-parse HEAD", { fixture = "git-outputs/rev-parse-head.txt" } },
		{ "git branch --show-current", { fixture = "git-outputs/branch-show-current.txt" } },

		-- git: file listings
		{ "--name-status", { fixture = "git-outputs/name-status-mixed.txt" } },
		{ "git ls-files", { fixture = "git-outputs/ls-files.txt" } },

		-- git: per-file diffs. Keyed on the pathspec, which the backend passes
		-- after a literal `--`.
		{ "-- README.md", { fixture = "git-outputs/diff-modified.txt" } },
		{ "-- src/app.lua", { fixture = "git-outputs/diff-multiple-hunks.txt" } },
		{ "-- src/new_feature.lua", { fixture = "git-outputs/diff-added.txt" } },
		{ "-- notes.txt", { fixture = "git-outputs/diff-deleted.txt" } },
		{ "-- docs/manual.md", { fixture = "git-outputs/diff-renamed.txt" } },
		{ "-- no-newline.txt", { fixture = "git-outputs/diff-no-trailing-newline.txt" } },
		{ "-- assets/logo.bin", { fixture = "git-outputs/diff-binary.txt" } },

		-- jj: repository identity
		{ "jj root", {
			stdout = function()
				return MockCli.root
			end,
		} },
		{ "--template change_id", { fixture = "jj-outputs/log-change-id.txt" } },
		{ "--template bookmarks", { fixture = "jj-outputs/log-bookmarks.txt" } },

		-- jj: file listings
		{ "jj status", { fixture = "jj-outputs/status-mixed.txt" } },
		{ "jj file list", { fixture = "jj-outputs/file-list.txt" } },

		-- jj: per-file diffs, keyed on the fileset literal.
		{ 'file:"README.md"', { fixture = "jj-outputs/diff-modified.txt" } },
		{ 'file:"src/app.lua"', { fixture = "jj-outputs/diff-multiple-hunks.txt" } },
		{ 'file:"src/new_feature.lua"', { fixture = "jj-outputs/diff-added.txt" } },
		{ 'file:"notes.txt"', { fixture = "jj-outputs/diff-deleted.txt" } },
		{ 'file:"docs/manual.md"', { fixture = "jj-outputs/diff-renamed.txt" } },
		{ 'file:"no-newline.txt"', { fixture = "jj-outputs/diff-no-trailing-newline.txt" } },
		{ 'file:"assets/logo.bin"', { fixture = "jj-outputs/diff-binary.txt" } },
	}

	for _, route in ipairs(defaults) do
		MockCli.set(route[1], route[2])
	end
end

---Turn a matched route's response into a CliResult.
---@param response table
---@return table result
local function to_result(response)
	if response.success ~= nil then
		return vim.deepcopy(response)
	end

	local stdout
	if response.fixture then
		stdout = MockCli.fixture(response.fixture)
	elseif type(response.stdout) == "function" then
		stdout = response.stdout()
	else
		stdout = response.stdout or ""
	end

	return { success = true, exit_code = 0, stdout = stdout, stderr = "" }
end

-- ---------------------------------------------------------------------------
-- The builder itself
-- ---------------------------------------------------------------------------

local Cli = {}
Cli.__index = Cli

---@return table builder
function Cli.new(cmd)
	return setmetatable({ cmd = cmd, args = {}, options = {}, _env = {} }, Cli)
end

function Cli:arg(value)
	table.insert(self.args, value)
	return self
end

function Cli:option(key, value)
	table.insert(self.args, "--" .. key)
	if value then
		table.insert(self.args, value)
	end
	return self
end

function Cli:flag(key)
	table.insert(self.args, "--" .. key)
	return self
end

function Cli:short_flag(key)
	table.insert(self.args, "-" .. key)
	return self
end

function Cli:env(key, value)
	self._env[key] = value
	return self
end

function Cli:cwd(dir)
	self.options.cwd = dir
	return self
end

function Cli:call()
	local cmdline = self.cmd .. " " .. table.concat(self.args, " ")
	table.insert(MockCli.calls, {
		cmd = self.cmd,
		args = vim.deepcopy(self.args),
		cwd = self.options.cwd,
		cmdline = cmdline,
	})

	for _, route in ipairs(MockCli.routes) do
		if cmdline:find(route.contains, 1, true) then
			return to_result(route.response)
		end
	end

	-- No route matched. Fail loudly enough that drift surfaces, but as a
	-- failure *result* rather than an error(): call() runs inside the plugin's
	-- own pcall and failure paths, where a bare error() would be swallowed and
	-- the miss would look like a successful empty result. `assert_no_misses`
	-- turns the record below into a test failure that names the command.
	local message = "mock_cli: no fixture routed for: " .. cmdline
	table.insert(MockCli.misses, cmdline)
	return { success = false, exit_code = 127, stdout = "", stderr = message }
end

function Cli:call_async()
	return self:call()
end

MockCli.module = Cli

-- ---------------------------------------------------------------------------
-- Installation
-- ---------------------------------------------------------------------------

local real_cli = nil

---Swap the mock in for the real CLI builder and clear every cached backend.
function MockCli.install()
	MockCli.reset()

	real_cli = real_cli or package.loaded["oversight.lib.cli"] or require("oversight.lib.cli")
	package.loaded["oversight.lib.cli"] = Cli

	-- git/cli.lua and jj/cli.lua capture the builder in an upvalue at their own
	-- load time, so swapping package.loaded is not enough on its own — they
	-- have to be dropped so the next require rebuilds them against the mock.
	-- The backends require them lazily, per call, so this takes effect at once.
	package.loaded["oversight.lib.vcs.git.cli"] = nil
	package.loaded["oversight.lib.vcs.jj.cli"] = nil

	MockCli.clear_backend_caches()
end

---Restore the real CLI builder.
function MockCli.uninstall()
	if real_cli then
		package.loaded["oversight.lib.cli"] = real_cli
	end
	package.loaded["oversight.lib.vcs.git.cli"] = nil
	package.loaded["oversight.lib.vcs.jj.cli"] = nil

	MockCli.clear_backend_caches()
end

---Drop the backends' singleton caches, which otherwise outlive the swap and
---hand a later test a backend still wired to the other CLI.
function MockCli.clear_backend_caches()
	require("oversight.lib.vcs").clear_cache()
end

MockCli.install_default_routes()

return MockCli
