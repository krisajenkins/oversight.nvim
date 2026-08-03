-- Tests for the jj CLI builder and the jj backend's parsing.
--
-- These used to guard every case with `if not isdirectory(cwd .. "/.jj")`, so
-- they were silent no-ops anywhere the plugin was not being developed in a jj
-- checkout — and where they did run, they asserted against whatever this
-- working copy happened to contain. They now run everywhere, against frozen
-- captures of real jj output (tests/fixtures/jj-outputs/).

local MockCli = require("tests.helpers.mock_cli")
local capture_notifications = require("tests.helpers.notify")

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["JJ CLI"] = MiniTest.new_set()

T["JJ CLI"]["builds root command"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	local builder = jj.root()

	expect.equality(builder.cmd, "jj")
	expect.equality(builder.args, { "root", "--no-pager" })
end

T["JJ CLI"]["builds status command with color=never"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	expect.equality(jj.status().args, { "status", "--no-pager", "--color", "never" })
end

T["JJ CLI"]["builds log command with color=never"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	expect.equality(jj.log().args, { "log", "--no-pager", "--no-graph", "--color", "never" })
end

-- Regression test. jj's default diff format is color-words, not unified, and
-- the backend hands this command's output straight to a unified-diff parser.
-- Without --git every file in a jj repository showed up with zero hunks, unless
-- the user happened to have set ui.diff-formatter = ":git" themselves.
T["JJ CLI"]["asks jj diff for git-format output"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	expect.equality(jj.diff().args, { "diff", "--no-pager", "--git", "--color", "never" })
end

T["JJ CLI"]["builds file list command"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	expect.equality(jj.file_list().args, { "file", "list", "--no-pager" })
end

T["JJ CLI"]["raw() still suppresses the pager"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	expect.equality(jj.raw():arg("status").args, { "--no-pager", "status" })
end

T["JJ CLI"]["option() adds key-value option"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	expect.equality(jj.raw():arg("log"):option("template", "change_id").args, {
		"--no-pager",
		"log",
		"--template",
		"change_id",
	})
end

T["JJ CLI"]["cwd() sets working directory"] = function()
	local jj = require("oversight.lib.vcs.jj.cli")

	expect.equality(jj.raw():cwd("/tmp").options.cwd, "/tmp")
end

-- ---------------------------------------------------------------------------
-- expand_rename_path (pure, no CLI involved)
-- ---------------------------------------------------------------------------

T["expand_rename_path"] = MiniTest.new_set()

local function expand(path)
	return require("oversight.lib.vcs.jj")._expand_rename_path(path)
end

T["expand_rename_path"]["expands simple rename"] = function()
	local old_path, new_path = expand("path/to/{old => new}/file.lua")

	expect.equality(old_path, "path/to/old/file.lua")
	expect.equality(new_path, "path/to/new/file.lua")
end

T["expand_rename_path"]["expands empty new part"] = function()
	local old_path, new_path = expand("lua/oversight/lib/{git => }/diff.lua")

	expect.equality(old_path, "lua/oversight/lib/git/diff.lua")
	expect.equality(new_path, "lua/oversight/lib/diff.lua")
end

T["expand_rename_path"]["expands empty old part"] = function()
	local old_path, new_path = expand("{=> new}/file.lua")

	expect.equality(old_path, "/file.lua")
	expect.equality(new_path, "new/file.lua")
end

T["expand_rename_path"]["returns plain path unchanged"] = function()
	local old_path, new_path = expand("simple/path.lua")

	expect.equality(old_path, "simple/path.lua")
	expect.equality(new_path, "simple/path.lua")
end

T["expand_rename_path"]["handles rename at start of path"] = function()
	local old_path, new_path = expand("{src => lib}/utils.lua")

	expect.equality(old_path, "src/utils.lua")
	expect.equality(new_path, "lib/utils.lua")
end

T["expand_rename_path"]["handles rename at end of path"] = function()
	local old_path, new_path = expand("path/to/{old.lua => new.lua}")

	expect.equality(old_path, "path/to/old.lua")
	expect.equality(new_path, "path/to/new.lua")
end

T["expand_rename_path"]["cleans double slashes from empty parts"] = function()
	local old_path, new_path = expand("a/{b => }/c.lua")

	expect.equality(old_path, "a/b/c.lua")
	expect.equality(new_path, "a/c.lua") -- Should NOT be "a//c.lua"
end

-- ---------------------------------------------------------------------------
-- Backend, against frozen captures
-- ---------------------------------------------------------------------------

local MOCK_ROOT = "/tmp/oversight-mock-repo"

T["JJ Backend"] = MiniTest.new_set({
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
	local Backend = require("oversight.lib.vcs.jj")
	local instance = Backend.instance(MOCK_ROOT)
	if not instance then
		error("expected the mock to produce a jj backend")
	end
	return instance
end

---@param path string
---@return FileDiff diff
local function diff_of(path)
	local diff = backend():get_file_diff(path)
	if not diff then
		error("expected a diff for " .. path)
	end
	return diff
end

T["JJ Backend"]["reads root, change ID and bookmark on construction"] = function()
	local repo = backend()

	expect.equality(repo.type, "jj")
	expect.equality(repo:get_root(), MOCK_ROOT)
	-- jj's change_id template prints the full 32-character ID, not the short
	-- prefix that `jj status` displays.
	expect.equality(repo:get_ref(), "pskzmqyvqskkzqrslpymqmytysvosurr")
	expect.equality(repo:get_branch(), "main")
end

T["JJ Backend"]["returns nil when the directory is not a jj repository"] = function()
	MockCli.set_failure("jj root", 'Error: There is no jj repo in "."')

	expect.equality(require("oversight.lib.vcs.jj").new("/tmp/definitely-not-a-repo"), nil)
end

T["JJ Backend"]["parses every status in jj status output"] = function()
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

-- jj prints two trailer lines after the change list, and a header before it.
-- None of them may be mistaken for a file.
T["JJ Backend"]["reports no changes for a clean working copy"] = function()
	MockCli.set("jj status", { fixture = "jj-outputs/status-clean.txt" })

	local repo = backend()

	expect.equality(repo:get_changed_files(), {})
	expect.equality(repo:has_changes(), false)
end

T["JJ Backend"]["has_changes is true when the working copy is dirty"] = function()
	expect.equality(backend():has_changes(), true)
end

T["JJ Backend"]["lists tracked files for browse mode"] = function()
	local files = backend():get_tracked_files()

	expect.equality(#files, 7)
	expect.equality(files[1], { status = "", path = "README.md" })
	expect.equality(files[7], { status = "", path = "src/util.lua" })
end

T["JJ Backend"]["parses a single-hunk diff"] = function()
	local diff = diff_of("README.md")

	expect.equality(diff.is_binary, false)
	expect.equality(#diff.hunks, 1)
end

T["JJ Backend"]["parses a diff with several hunks"] = function()
	expect.equality(#diff_of("src/app.lua").hunks, 2)
end

T["JJ Backend"]["parses a pure-addition diff"] = function()
	local diff = diff_of("src/new_feature.lua")

	expect.equality(#diff.hunks, 1)
	for _, line in ipairs(diff.hunks[1].lines) do
		expect.equality(line.type, "add")
	end
end

T["JJ Backend"]["parses a pure-deletion diff"] = function()
	local diff = diff_of("notes.txt")

	expect.equality(#diff.hunks, 1)
	for _, line in ipairs(diff.hunks[1].lines) do
		expect.equality(line.type, "delete")
	end
end

T["JJ Backend"]["marks binary files as binary"] = function()
	local diff = diff_of("assets/logo.bin")

	expect.equality(diff.is_binary, true)
	expect.equality(#diff.hunks, 0)
end

T["JJ Backend"]["drops the no-trailing-newline marker"] = function()
	local diff = diff_of("no-newline.txt")

	expect.equality(#diff.hunks, 1)
	expect.equality(#diff.hunks[1].lines, 2)
end

-- jj reports a pure rename as a header-only diff with no hunks at all. That has
-- to survive as an empty-but-valid FileDiff rather than a nil.
T["JJ Backend"]["handles a rename with no content change"] = function()
	local diff = diff_of("docs/manual.md")

	expect.equality(diff.is_binary, false)
	expect.equality(diff.hunks, {})
end

T["JJ Backend"]["returns nil and notifies when the diff command fails"] = function()
	MockCli.set_failure('file:"src/util.lua"', "Error: No such path")

	local messages = capture_notifications(function()
		expect.equality(backend():get_file_diff("src/util.lua"), nil)
	end)

	expect.equality(#messages, 1)
	expect.equality(messages[1]:find("src/util.lua", 1, true) ~= nil, true)
end

-- Regression test for paths that look like glob patterns. The backend wraps
-- every path in a `file:"..."` fileset literal precisely so jj does not treat
-- the brackets as a pattern.
T["JJ Backend"]["quotes paths as fileset literals"] = function()
	MockCli.set('file:"[year]/[slug].astro"', { stdout = "" })

	diff_of("[year]/[slug].astro")

	local last = MockCli.calls[#MockCli.calls]
	expect.equality(last.cmdline:find('file:"[year]/[slug].astro"', 1, true) ~= nil, true)
end

T["JJ Backend"]["escapes double quotes in paths"] = function()
	MockCli.set('file:"file\\"with\\"quotes.lua"', { stdout = "" })

	diff_of('file"with"quotes.lua')

	local last = MockCli.calls[#MockCli.calls]
	expect.equality(last.cmdline:find('file:"file\\"with\\"quotes.lua"', 1, true) ~= nil, true)
end

T["JJ Backend"]["refresh() re-reads change ID and bookmark"] = function()
	local repo = backend()

	MockCli.set("--template change_id", { stdout = "zzzzzzzzzzzz" })
	MockCli.set("--template bookmarks", { stdout = "" })
	repo:refresh()

	expect.equality(repo:get_ref(), "zzzzzzzzzzzz")
	-- No bookmark points at @, which jj reports as empty output.
	expect.equality(repo:get_branch(), nil)
end

return T
