-- Tests for markdown export

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Export"] = MiniTest.new_set()

-- Mock repository for testing
local function create_mock_repo()
	return {
		get_root = function()
			return "/tmp/test-repo"
		end,
		get_branch = function()
			return "main"
		end,
		get_head = function()
			return "abc123def456"
		end,
	}
end

T["Export"]["generates markdown header"] = function()
	local Export = require("oversight.lib.export")
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	local repo = create_mock_repo()

	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("# Code Review: test%-repo @ abc123de") ~= nil, true)
end

T["Export"]["formats comments by file"] = function()
	local Export = require("oversight.lib.export")
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("src/main.lua", 10, "new", "issue", "Fix this bug")
	session:add_comment("src/utils.lua", 5, "new", "suggestion", "Consider refactoring")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("## src/main%.lua") ~= nil, true)
	expect.equality(markdown:match("## src/utils%.lua") ~= nil, true)
	expect.equality(markdown:match("Fix this bug") ~= nil, true)
	expect.equality(markdown:match("Consider refactoring") ~= nil, true)
end

T["Export"]["includes line numbers"] = function()
	local Export = require("oversight.lib.export")
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("test.lua", 42, "new", "issue", "Problem here")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("Line 42") ~= nil, true)
end

T["Export"]["marks deleted lines with tilde"] = function()
	local Export = require("oversight.lib.export")
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("test.lua", 10, "old", "note", "This was removed")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("~10") ~= nil, true)
end

T["Export"]["handles file-level comments"] = function()
	local Export = require("oversight.lib.export")
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("test.lua", nil, nil, "note", "General comment about this file")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("file%-level") ~= nil, true)
	expect.equality(markdown:match("General comment about this file") ~= nil, true)
end

return T
