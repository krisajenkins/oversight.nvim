-- Tests for storage/session functionality

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Session"] = MiniTest.new_set()

T["Session"]["creates new session"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	expect.equality(session.repo_root, "/tmp/test-repo")
	expect.equality(session.base_ref, "abc123")
	expect.equality(session.version, "1.0")
	expect.equality(#session.comments, 0)
end

T["Session"]["adds comments"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	local comment = session:add_comment("test.lua", 10, "new", "issue", "This is a problem")

	expect.equality(#session.comments, 1)
	expect.equality(comment.file, "test.lua")
	expect.equality(comment.line, 10)
	expect.equality(comment.side, "new")
	expect.equality(comment.type, "issue")
	expect.equality(comment.text, "This is a problem")
end

T["Session"]["adds file-level comments"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	local comment = session:add_comment("test.lua", nil, nil, "note", "General observation")

	expect.equality(comment.line, nil)
	expect.equality(comment.side, nil)
end

T["Session"]["deletes comments"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	local comment = session:add_comment("test.lua", 10, "new", "issue", "Problem")
	expect.equality(#session.comments, 1)

	local deleted = session:delete_comment(comment.id)
	expect.equality(deleted, true)
	expect.equality(#session.comments, 0)
end

T["Session"]["tracks file status"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	session:ensure_file("src/main.lua", "M")

	expect.equality(session:is_file_reviewed("src/main.lua"), false)

	session:set_file_reviewed("src/main.lua", true)
	expect.equality(session:is_file_reviewed("src/main.lua"), true)
end

T["Session"]["toggles file reviewed status"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	session:ensure_file("test.lua", "A")
	expect.equality(session:is_file_reviewed("test.lua"), false)

	session:toggle_file_reviewed("test.lua")
	expect.equality(session:is_file_reviewed("test.lua"), true)

	session:toggle_file_reviewed("test.lua")
	expect.equality(session:is_file_reviewed("test.lua"), false)
end

T["Session"]["calculates progress"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	session:ensure_file("file1.lua", "M")
	session:ensure_file("file2.lua", "A")
	session:ensure_file("file3.lua", "D")

	local reviewed, total = session:get_progress()
	expect.equality(reviewed, 0)
	expect.equality(total, 3)

	session:set_file_reviewed("file1.lua", true)
	reviewed, total = session:get_progress()
	expect.equality(reviewed, 1)
	expect.equality(total, 3)
end

T["Session"]["gets comments by file"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	session:add_comment("file1.lua", 10, "new", "note", "Comment 1")
	session:add_comment("file1.lua", 20, "new", "issue", "Comment 2")
	session:add_comment("file2.lua", 5, "old", "suggestion", "Comment 3")

	local file1_comments = session:get_file_comments("file1.lua")
	expect.equality(#file1_comments, 2)

	local file2_comments = session:get_file_comments("file2.lua")
	expect.equality(#file2_comments, 1)

	local file3_comments = session:get_file_comments("file3.lua")
	expect.equality(#file3_comments, 0)
end

T["Session"]["gets comment counts by type"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	session:add_comment("test.lua", 1, "new", "note", "Note 1")
	session:add_comment("test.lua", 2, "new", "note", "Note 2")
	session:add_comment("test.lua", 3, "new", "issue", "Issue 1")
	session:add_comment("test.lua", 4, "new", "suggestion", "Suggestion 1")

	local counts = session:get_comment_counts()

	expect.equality(counts.note, 2)
	expect.equality(counts.issue, 1)
	expect.equality(counts.suggestion, 1)
	expect.equality(counts.praise, 0)
end

T["Session"]["serializes to JSON and back"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	session:ensure_file("test.lua", "M")
	session:add_comment("test.lua", 10, "new", "issue", "Problem")

	local json_data = session:to_json()
	local restored = Session.from_json(json_data)

	expect.equality(restored.repo_root, session.repo_root)
	expect.equality(restored.base_ref, session.base_ref)
	expect.equality(#restored.comments, 1)
	expect.equality(restored.comments[1].text, "Problem")
end

T["Session"]["checks for comments"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")
	expect.equality(session:has_comments(), false)

	session:add_comment("test.lua", 10, "new", "note", "Comment")
	expect.equality(session:has_comments(), true)
end

return T
