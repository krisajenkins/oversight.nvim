-- Tests for the git CLI builder and the git backend's parsing.
--
-- Nothing here shells out. The command builders are pure, and the backend runs
-- against tests/helpers/mock_cli.lua replaying frozen captures of real git
-- output. tests/test_vcs_hermetic.lua is the one place a real git binary runs,
-- and it is what keeps these fixtures honest.

local MockCli = require("tests.helpers.mock_cli")
local capture_notifications = require("tests.helpers.notify")

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Git CLI"] = MiniTest.new_set()

T["Git CLI"]["builds diff command"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.diff()

	expect.equality(builder.cmd, "git")
	expect.equality(builder.args, { "diff", "--no-color" })
end

T["Git CLI"]["builds status command"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	expect.equality(git.status().args, { "status" })
end

T["Git CLI"]["builds rev-parse command"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	expect.equality(git.rev_parse().args, { "rev-parse" })
end

T["Git CLI"]["arg() adds positional arguments in order"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.raw():arg("log"):arg("-n"):arg("5")

	expect.equality(builder.args, { "log", "-n", "5" })
end

T["Git CLI"]["flag() adds flag with double dash"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	expect.equality(git.raw():arg("status"):flag("porcelain").args, { "status", "--porcelain" })
end

T["Git CLI"]["short_flag() adds flag with single dash"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	expect.equality(git.raw():arg("log"):short_flag("n").args, { "log", "-n" })
end

T["Git CLI"]["option() adds key-value option"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	expect.equality(git.raw():arg("log"):option("format", "%H").args, { "log", "--format", "%H" })
end

T["Git CLI"]["cwd() sets working directory"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	expect.equality(git.raw():cwd("/tmp").options.cwd, "/tmp")
end

T["Git CLI"]["chaining works correctly"] = function()
	local git = require("oversight.lib.vcs.git.cli")

	local builder = git.diff():arg("HEAD"):flag("stat"):cwd("/tmp")

	expect.equality(builder.args, { "diff", "--no-color", "HEAD", "--stat" })
	expect.equality(builder.options.cwd, "/tmp")
end

-- ---------------------------------------------------------------------------
-- Backend, against frozen captures
-- ---------------------------------------------------------------------------

local MOCK_ROOT = "/tmp/oversight-mock-repo"

T["Git Backend"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			MockCli.install()
		end,
		post_case = function()
			MockCli.assert_no_misses()
			MockCli.uninstall()
		end,
	},
})

---@return VcsBackend backend
local function backend()
	local Backend = require("oversight.lib.vcs.git")
	local instance = Backend.instance(MOCK_ROOT)
	if not instance then
		error("expected the mock to produce a git backend")
	end
	return instance
end

---Fetch a file's base content, failing the test rather than the assertion if it
---is nil.
---@param path string
---@return string[] lines
local function base_of(path)
	local lines = backend():get_file_at_base(path)
	if not lines then
		error("expected base content for " .. path)
	end
	return lines
end

T["Git Backend"]["reads root, ref and branch on construction"] = function()
	local repo = backend()

	expect.equality(repo.type, "git")
	expect.equality(repo:get_root(), MOCK_ROOT)
	expect.equality(repo:get_ref(), "9b5dc541dd260fc24a5b8875e8ab33214770cb96")
	expect.equality(repo:get_branch(), "main")
end

T["Git Backend"]["returns nil when the directory is not a repository"] = function()
	MockCli.set_failure("rev-parse --git-dir", "fatal: not a git repository")

	local Backend = require("oversight.lib.vcs.git")

	expect.equality(Backend.new("/tmp/definitely-not-a-repo"), nil)
end

T["Git Backend"]["parses every status in --name-status output"] = function()
	local files = backend():get_changed_files()

	expect.equality(files, {
		{ status = "M", path = "README.md" },
		{ status = "M", path = "assets/logo.bin" },
		{ status = "R", path = "docs/manual.md", old_path = "docs/guide.md" },
		{ status = "M", path = "no-newline.txt" },
		{ status = "D", path = "notes.txt" },
		{ status = "M", path = "src/app.lua" },
		{ status = "A", path = "src/new_feature.lua" },
	})
end

-- Regression test. `--name-status` is TAB-separated, but the rename branch used
-- to split the path field on whitespace with "^(.+)%s+(.+)$". Given
-- "R100\told name.md\tnew name.md" that split at the last space, producing
-- old_path "docs/old name.md\tnew" and path "name.md".
T["Git Backend"]["splits rename fields on tabs, not spaces"] = function()
	MockCli.set("--name-status", { fixture = "git-outputs/name-status-spaces.txt" })

	local files = backend():get_changed_files()

	expect.equality(files, {
		{ status = "M", path = "docs/release notes.md" },
		{ status = "R", path = "docs/new name.md", old_path = "docs/old name.md" },
		{ status = "A", path = "src/with space.lua" },
	})
end

T["Git Backend"]["parses copies, which carry a source path like renames"] = function()
	MockCli.set("--name-status", { fixture = "git-outputs/name-status-copied.txt" })

	local files = backend():get_changed_files()

	expect.equality(files, {
		{ status = "M", path = "src/app.lua" },
		{ status = "C", path = "src/app_copy.lua", old_path = "src/app.lua" },
	})
end

T["Git Backend"]["reports no changes for a clean working tree"] = function()
	MockCli.set("--name-status", { stdout = "" })

	local repo = backend()

	expect.equality(repo:get_changed_files(), {})
	expect.equality(repo:has_changes(), false)
end

T["Git Backend"]["has_changes is true when the tree is dirty"] = function()
	expect.equality(backend():has_changes(), true)
end

T["Git Backend"]["lists tracked files for browse mode"] = function()
	local files = backend():get_tracked_files()

	expect.equality(#files, 7)
	expect.equality(files[1], { status = "", path = "README.md" })
	-- Wider than the change list: util.lua is tracked but untouched.
	expect.equality(files[7], { status = "", path = "src/util.lua" })
end

-- The diff view never parses a diff: it is handed the file at the base revision
-- and the file now, and Neovim works out the rest. These check the first half.

T["Git Backend"]["reads a modified file's content at HEAD"] = function()
	expect.equality(base_of("README.md"), {
		"# Demo",
		"",
		"A repository that exists only to produce test fixtures.",
	})
end

-- The working copy is read with `readfile`, which cannot represent a trailing
-- newline either. If the two disagreed, every file in the repository would show
-- a spurious last-line change.
T["Git Backend"]["reads a file with no trailing newline as one line"] = function()
	expect.equality(base_of("no-newline.txt"), { "no trailing newline here" })
end

-- A rename is read under its OLD name: that is what the content was called at
-- HEAD, and the new name does not exist there.
T["Git Backend"]["reads a renamed file under its old path"] = function()
	expect.equality(base_of("docs/guide.md"), { "# Guide", "", "Read this first." })
end

T["Git Backend"]["reads a deleted file, which still exists at HEAD"] = function()
	expect.equality(base_of("notes.txt"), { "Scratch notes.", "Delete me." })
end

-- An added file has no content at HEAD, and git says so on stderr rather than
-- printing nothing. That is a normal answer, not an error: empty lines, not nil.
T["Git Backend"]["reports an added file as empty at HEAD, not as a failure"] = function()
	local messages = capture_notifications(function()
		expect.equality(backend():get_file_at_base("src/new_feature.lua"), {})
	end)

	expect.equality(messages, {})
end

T["Git Backend"]["returns nil and notifies when reading at HEAD fails"] = function()
	MockCli.set_failure("HEAD:src/util.lua", "fatal: bad object HEAD", 128)

	local messages = capture_notifications(function()
		expect.equality(backend():get_file_at_base("src/util.lua"), nil)
	end)

	expect.equality(#messages, 1)
	expect.equality(tostring(messages[1].msg):find("src/util.lua", 1, true) ~= nil, true)
end

-- Not for display: `Session:ensure_file` hashes this to notice a file's changes
-- moving under a review, which is what drops its comments.
T["Git Backend"]["hands back raw diff output for change detection"] = function()
	local raw = backend():get_file_diff_raw("README.md")

	expect.equality(type(raw), "string")
	expect.equality(raw:find("@@", 1, true) ~= nil, true)
end

T["Git Backend"]["returns nil raw diff when the diff command fails"] = function()
	MockCli.set_failure("-- src/util.lua", "fatal: bad revision")

	expect.equality(backend():get_file_diff_raw("src/util.lua"), nil)
end

T["Git Backend"]["instance() caches per directory"] = function()
	local Backend = require("oversight.lib.vcs.git")

	local first = Backend.instance(MOCK_ROOT)
	expect.equality(rawequal(first, Backend.instance(MOCK_ROOT)), true)

	Backend.clear_cache()
	expect.equality(rawequal(first, Backend.instance(MOCK_ROOT)), false)
end

T["Git Backend"]["refresh() re-reads ref and branch"] = function()
	local repo = backend()

	MockCli.set("rev-parse HEAD", { stdout = "0000000000000000000000000000000000000000" })
	MockCli.set("branch --show-current", { stdout = "other-branch" })
	repo:refresh()

	expect.equality(repo:get_ref(), "0000000000000000000000000000000000000000")
	expect.equality(repo:get_branch(), "other-branch")
end

T["Git Backend"]["refresh() reports a detached HEAD as no branch"] = function()
	local repo = backend()

	-- `git branch --show-current` succeeds but prints nothing when detached.
	MockCli.set("branch --show-current", { stdout = "" })
	repo:refresh()

	expect.equality(repo:get_branch(), nil)
end

return T
