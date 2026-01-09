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
	local Export = require("tuicr.lib.export")
	local Session = require("tuicr.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	local repo = create_mock_repo()

	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("# Code Review Feedback") ~= nil, true)
	expect.equality(markdown:match("Repository: test%-repo") ~= nil, true)
	expect.equality(markdown:match("Branch: main") ~= nil, true)
end

T["Export"]["includes comment types explanation"] = function()
	local Export = require("tuicr.lib.export")
	local Session = require("tuicr.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	local repo = create_mock_repo()

	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("ISSUE") ~= nil, true)
	expect.equality(markdown:match("SUGGESTION") ~= nil, true)
	expect.equality(markdown:match("NOTE") ~= nil, true)
	expect.equality(markdown:match("PRAISE") ~= nil, true)
end

T["Export"]["formats comments by file"] = function()
	local Export = require("tuicr.lib.export")
	local Session = require("tuicr.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("src/main.lua", 10, "new", "issue", "Fix this bug")
	session:add_comment("src/utils.lua", 5, "new", "suggestion", "Consider refactoring")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("### src/main%.lua") ~= nil, true)
	expect.equality(markdown:match("### src/utils%.lua") ~= nil, true)
	expect.equality(markdown:match("Fix this bug") ~= nil, true)
	expect.equality(markdown:match("Consider refactoring") ~= nil, true)
end

T["Export"]["includes line numbers"] = function()
	local Export = require("tuicr.lib.export")
	local Session = require("tuicr.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("test.lua", 42, "new", "issue", "Problem here")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("Line 42") ~= nil, true)
end

T["Export"]["marks deleted lines with tilde"] = function()
	local Export = require("tuicr.lib.export")
	local Session = require("tuicr.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("test.lua", 10, "old", "note", "This was removed")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("~10") ~= nil, true)
end

T["Export"]["handles file-level comments"] = function()
	local Export = require("tuicr.lib.export")
	local Session = require("tuicr.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:add_comment("test.lua", nil, nil, "note", "General comment about this file")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("file%-level") ~= nil, true)
	expect.equality(markdown:match("General comment about this file") ~= nil, true)
end

T["Export"]["includes summary with counts"] = function()
	local Export = require("tuicr.lib.export")
	local Session = require("tuicr.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:ensure_file("file1.lua", "M")
	session:ensure_file("file2.lua", "A")
	session:set_file_reviewed("file1.lua", true)

	session:add_comment("file1.lua", 1, "new", "issue", "Issue 1")
	session:add_comment("file1.lua", 2, "new", "issue", "Issue 2")
	session:add_comment("file1.lua", 3, "new", "suggestion", "Suggestion 1")

	local repo = create_mock_repo()
	local markdown = Export.to_markdown(session, repo)

	expect.equality(markdown:match("Files reviewed: 1/2") ~= nil, true)
	expect.equality(markdown:match("Total comments: 3") ~= nil, true)
	expect.equality(markdown:match("Issues: 2") ~= nil, true)
	expect.equality(markdown:match("Suggestions: 1") ~= nil, true)
end

return T
