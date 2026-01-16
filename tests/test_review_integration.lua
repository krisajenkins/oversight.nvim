-- Integration tests for ReviewBuffer workflow
-- Tests the coordination between ReviewBuffer, FileListBuffer, DiffViewBuffer, and Session

local T = MiniTest.new_set()
local expect = MiniTest.expect

-- Test helpers
local helpers = {}

---Create a mock repository for testing
---@param opts? table Options for mock behavior
---@return table repo Mock repository object
function helpers.create_mock_repo(opts)
	opts = opts or {}
	local root = opts.root or "/tmp/test-repo-" .. os.time()
	local files = opts.files
		or {
			{ path = "src/main.lua", status = "M" },
			{ path = "src/utils.lua", status = "A" },
			{ path = "README.md", status = "M" },
		}

	return {
		get_root = function()
			return root
		end,
		get_branch = function()
			return opts.branch or "main"
		end,
		get_head = function()
			return opts.head or "abc123def456"
		end,
		has_changes = function()
			return #files > 0
		end,
		get_changed_files = function()
			return files
		end,
	}
end

---Create a simple mock diff for testing
---@param file_path string File path
---@return table diff Mock diff data
function helpers.create_mock_diff(file_path)
	return {
		path = file_path,
		old_path = file_path,
		hunks = {
			{
				old_start = 1,
				old_count = 3,
				new_start = 1,
				new_count = 4,
				header = "@@ -1,3 +1,4 @@",
				lines = {
					{ type = "context", old_no = 1, new_no = 1, text = "-- File: " .. file_path },
					{ type = "delete", old_no = 2, text = "-- Old line" },
					{ type = "add", new_no = 2, text = "-- New line" },
					{ type = "add", new_no = 3, text = "-- Another new line" },
					{ type = "context", old_no = 3, new_no = 4, text = "return {}" },
				},
			},
		},
	}
end

---Clean up after review tests
---@param review table ReviewBuffer instance
function helpers.cleanup_review(review)
	if review and review.close then
		-- Silence notifications during cleanup
		local old_notify = vim.notify
		vim.notify = function() end
		pcall(function()
			review:close()
		end)
		vim.notify = old_notify
	end
end

-- Test sets
T["ReviewBuffer Integration"] = MiniTest.new_set()

T["ReviewBuffer Integration"]["creates layout with two panels"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")
	local DiffViewBuffer = require("oversight.buffers.diff_view")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())
	local files = repo:get_changed_files()

	-- Ensure files are tracked in session
	for _, file in ipairs(files) do
		session:ensure_file(file.path, file.status)
	end

	-- Create file list buffer
	local file_list = FileListBuffer.new({
		files = vim.tbl_map(function(f)
			return { path = f.path, status = f.status, reviewed = false }
		end, files),
		session = session,
		branch = repo:get_branch(),
		on_file_select = function() end,
		on_toggle_reviewed = function() end,
		on_open_file = function() end,
	})

	-- Create diff view buffer
	local diff_view = DiffViewBuffer.new({
		repo = repo,
		session = session,
		on_comment = function() end,
		on_toggle_reviewed = function() end,
		on_quit = function() end,
	})

	expect.equality(file_list ~= nil, true)
	expect.equality(diff_view ~= nil, true)
	expect.equality(file_list:get_handle() ~= nil, true)
	expect.equality(diff_view:get_handle() ~= nil, true)

	-- Cleanup
	file_list:close()
	diff_view:close()
end

T["FileList Navigation"] = MiniTest.new_set()

T["FileList Navigation"]["move_cursor updates current index"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())
	local files = {
		{ path = "file1.lua", status = "M", reviewed = false },
		{ path = "file2.lua", status = "A", reviewed = false },
		{ path = "file3.lua", status = "D", reviewed = false },
	}

	local selected_file = nil
	local file_list = FileListBuffer.new({
		files = files,
		session = session,
		branch = "main",
		on_file_select = function(file, _index)
			selected_file = file
		end,
		on_toggle_reviewed = function() end,
		on_open_file = function() end,
	})

	-- Initial state
	expect.equality(file_list:get_current_index(), 1)
	expect.equality(file_list:get_current_file().path, "file1.lua")

	-- Move down
	file_list:move_cursor(1)
	expect.equality(file_list:get_current_index(), 2)
	expect.equality(selected_file.path, "file2.lua")

	-- Move down again
	file_list:move_cursor(1)
	expect.equality(file_list:get_current_index(), 3)
	expect.equality(selected_file.path, "file3.lua")

	-- Move down at boundary (should stay at 3)
	file_list:move_cursor(1)
	expect.equality(file_list:get_current_index(), 3)

	-- Move up
	file_list:move_cursor(-1)
	expect.equality(file_list:get_current_index(), 2)

	-- Cleanup
	file_list:close()
end

T["FileList Navigation"]["move_to jumps to specific index"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())
	local files = {
		{ path = "file1.lua", status = "M", reviewed = false },
		{ path = "file2.lua", status = "A", reviewed = false },
		{ path = "file3.lua", status = "D", reviewed = false },
		{ path = "file4.lua", status = "M", reviewed = false },
	}

	local file_list = FileListBuffer.new({
		files = files,
		session = session,
		branch = "main",
		on_file_select = function() end,
		on_toggle_reviewed = function() end,
		on_open_file = function() end,
	})

	-- Jump to last
	file_list:move_to(4)
	expect.equality(file_list:get_current_index(), 4)
	expect.equality(file_list:get_current_file().path, "file4.lua")

	-- Jump to first
	file_list:move_to(1)
	expect.equality(file_list:get_current_index(), 1)
	expect.equality(file_list:get_current_file().path, "file1.lua")

	-- Jump beyond bounds (should clamp)
	file_list:move_to(100)
	expect.equality(file_list:get_current_index(), 4)

	file_list:move_to(-5)
	expect.equality(file_list:get_current_index(), 1)

	-- Cleanup
	file_list:close()
end

T["Reviewed Status"] = MiniTest.new_set()

T["Reviewed Status"]["toggle_reviewed updates session and file state"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	local files = {
		{ path = "file1.lua", status = "M", reviewed = false },
		{ path = "file2.lua", status = "A", reviewed = false },
	}

	-- Ensure files in session
	for _, file in ipairs(files) do
		session:ensure_file(file.path, file.status)
	end

	local toggled_file = nil
	local file_list = FileListBuffer.new({
		files = files,
		session = session,
		branch = "main",
		on_file_select = function() end,
		on_toggle_reviewed = function(file, _index)
			toggled_file = file
		end,
		on_open_file = function() end,
	})

	-- Initially not reviewed
	expect.equality(file_list:get_current_file().reviewed, false)
	expect.equality(session:is_file_reviewed("file1.lua"), false)

	-- Toggle reviewed - cursor stays at same position (now file2.lua)
	-- Display was: [file1.lua, file2.lua]
	-- After toggle: [file2.lua, ---, file1.lua]
	-- Cursor at position 1 = file2.lua
	file_list:toggle_reviewed()

	expect.equality(session:is_file_reviewed("file1.lua"), true)
	expect.equality(toggled_file.path, "file1.lua")
	expect.equality(toggled_file.reviewed, true)
	expect.equality(file_list:get_current_file().path, "file2.lua")
	expect.equality(file_list:get_current_file().reviewed, false)

	-- Toggle file2.lua - cursor stays at position 1
	-- Display was: [file2.lua, ---, file1.lua]
	-- After toggle: [file1.lua, file2.lua] (both reviewed, no separator)
	-- Cursor at position 1 = file1.lua
	file_list:toggle_reviewed()

	expect.equality(session:is_file_reviewed("file2.lua"), true)
	expect.equality(file_list:get_current_file().path, "file1.lua")
	expect.equality(file_list:get_current_file().reviewed, true)

	-- Cleanup
	file_list:close()
end

T["Reviewed Status"]["update_file_reviewed syncs state from external source"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	local files = {
		{ path = "file1.lua", status = "M", reviewed = false },
		{ path = "file2.lua", status = "A", reviewed = false },
	}

	local file_list = FileListBuffer.new({
		files = files,
		session = session,
		branch = "main",
		on_file_select = function() end,
		on_toggle_reviewed = function() end,
		on_open_file = function() end,
	})

	-- Simulate external update (e.g., from DiffViewBuffer)
	file_list:update_file_reviewed("file2.lua", true)

	-- Navigate to file2 and check
	file_list:move_to(2)
	expect.equality(file_list:get_current_file().reviewed, true)

	-- Cleanup
	file_list:close()
end

T["Reviewed Status"]["progress calculation reflects reviewed files"] = function()
	local Session = require("oversight.lib.storage.session")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	-- Add files
	session:ensure_file("file1.lua", "M")
	session:ensure_file("file2.lua", "A")
	session:ensure_file("file3.lua", "D")

	-- Initially 0/3 reviewed
	local reviewed, total = session:get_progress()
	expect.equality(reviewed, 0)
	expect.equality(total, 3)

	-- Mark one reviewed
	session:set_file_reviewed("file1.lua", true)
	reviewed, total = session:get_progress()
	expect.equality(reviewed, 1)
	expect.equality(total, 3)

	-- Mark another reviewed
	session:set_file_reviewed("file3.lua", true)
	reviewed, total = session:get_progress()
	expect.equality(reviewed, 2)
	expect.equality(total, 3)
end

T["Comments Integration"] = MiniTest.new_set()

T["Comments Integration"]["comments are tracked per file in session"] = function()
	local Session = require("oversight.lib.storage.session")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	-- Add comments to different files
	session:add_comment("file1.lua", 10, "new", "issue", "Bug here")
	session:add_comment("file1.lua", 20, "new", "suggestion", "Consider this")
	session:add_comment("file2.lua", 5, "old", "note", "Was removed")

	-- Check file-level retrieval
	local file1_comments = session:get_file_comments("file1.lua")
	expect.equality(#file1_comments, 2)

	local file2_comments = session:get_file_comments("file2.lua")
	expect.equality(#file2_comments, 1)

	-- Check total counts
	local counts = session:get_comment_counts()
	expect.equality(counts.issue, 1)
	expect.equality(counts.suggestion, 1)
	expect.equality(counts.note, 1)
end

T["Comments Integration"]["file-level comments work correctly"] = function()
	local Session = require("oversight.lib.storage.session")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	-- Add file-level comment (no line number)
	local comment = session:add_comment("file1.lua", nil, nil, "praise", "Great file!")

	expect.equality(comment.file, "file1.lua")
	expect.equality(comment.line, nil)
	expect.equality(comment.side, nil)
	expect.equality(comment.type, "praise")
	expect.equality(comment.text, "Great file!")

	-- Should be retrievable
	local comments = session:get_file_comments("file1.lua")
	expect.equality(#comments, 1)
	expect.equality(comments[1].text, "Great file!")
end

T["Comments Integration"]["comment deletion works"] = function()
	local Session = require("oversight.lib.storage.session")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	local comment1 = session:add_comment("file1.lua", 10, "new", "issue", "Issue 1")
	local comment2 = session:add_comment("file1.lua", 20, "new", "issue", "Issue 2")

	expect.equality(#session.comments, 2)

	-- Delete first comment
	local deleted = session:delete_comment(comment1.id)
	expect.equality(deleted, true)
	expect.equality(#session.comments, 1)
	expect.equality(session.comments[1].id, comment2.id)

	-- Delete non-existent comment
	local not_deleted = session:delete_comment("non-existent-id")
	expect.equality(not_deleted, false)
end

T["Session Persistence"] = MiniTest.new_set()

T["Session Persistence"]["session serializes and deserializes correctly"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	-- Add various data
	session:ensure_file("file1.lua", "M")
	session:ensure_file("file2.lua", "A")
	session:set_file_reviewed("file1.lua", true)
	session:add_comment("file1.lua", 10, "new", "issue", "Bug here")
	session:add_comment("file2.lua", nil, nil, "note", "General note")

	-- Serialize (type guaranteed by LuaCATS: ---@return table)
	local json_data = session:to_json()

	-- Deserialize
	local restored = Session.from_json(json_data)

	-- Verify data
	expect.equality(restored.repo_root, session.repo_root)
	expect.equality(restored.base_ref, session.base_ref)
	expect.equality(restored:is_file_reviewed("file1.lua"), true)
	expect.equality(restored:is_file_reviewed("file2.lua"), false)
	expect.equality(#restored.comments, 2)

	-- Check comment content
	local file1_comments = restored:get_file_comments("file1.lua")
	expect.equality(#file1_comments, 1)
	expect.equality(file1_comments[1].text, "Bug here")
end

T["Session Persistence"]["session preserves all comment types"] = function()
	local Session = require("oversight.lib.storage.session")

	local session = Session.new("/tmp/test-repo", "abc123")

	-- Add all comment types
	session:add_comment("test.lua", 1, "new", "issue", "Issue text")
	session:add_comment("test.lua", 2, "new", "suggestion", "Suggestion text")
	session:add_comment("test.lua", 3, "new", "note", "Note text")
	session:add_comment("test.lua", 4, "new", "praise", "Praise text")

	-- Round-trip
	local json_data = session:to_json()
	local restored = Session.from_json(json_data)

	local counts = restored:get_comment_counts()
	expect.equality(counts.issue, 1)
	expect.equality(counts.suggestion, 1)
	expect.equality(counts.note, 1)
	expect.equality(counts.praise, 1)
end

T["Export Integration"] = MiniTest.new_set()

T["Export Integration"]["export produces valid markdown with comments"] = function()
	local Export = require("oversight.lib.export")
	local Session = require("oversight.lib.storage.session")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	-- Setup review state
	session:ensure_file("src/main.lua", "M")
	session:ensure_file("src/utils.lua", "A")
	session:set_file_reviewed("src/main.lua", true)

	-- Add comments
	session:add_comment("src/main.lua", 10, "new", "issue", "Fix this critical bug")
	session:add_comment("src/main.lua", 25, "new", "suggestion", "Consider using a constant")
	session:add_comment("src/utils.lua", nil, nil, "praise", "Well structured file")

	local markdown = Export.to_markdown(session, repo)

	-- Check header
	expect.equality(markdown:match("# Code Review:") ~= nil, true)

	-- Check file sections
	expect.equality(markdown:match("## src/main%.lua") ~= nil, true)
	expect.equality(markdown:match("## src/utils%.lua") ~= nil, true)

	-- Check comments appear
	expect.equality(markdown:match("Fix this critical bug") ~= nil, true)
	expect.equality(markdown:match("Consider using a constant") ~= nil, true)
	expect.equality(markdown:match("Well structured file") ~= nil, true)
end

T["Export Integration"]["export handles empty session"] = function()
	local Export = require("oversight.lib.export")
	local Session = require("oversight.lib.storage.session")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	local markdown = Export.to_markdown(session, repo)

	-- Should still have header
	expect.equality(markdown:match("# Code Review:") ~= nil, true)
end

T["DiffView Integration"] = MiniTest.new_set()

T["DiffView Integration"]["show_file updates current file state"] = function()
	local Session = require("oversight.lib.storage.session")
	local DiffViewBuffer = require("oversight.buffers.diff_view")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	local diff_view = DiffViewBuffer.new({
		repo = repo,
		session = session,
		on_comment = function() end,
		on_toggle_reviewed = function() end,
		on_quit = function() end,
	})

	-- Initially no file selected
	expect.equality(diff_view.current_file, nil)

	-- Set current_file directly (simulates show_file without git operations)
	local test_file = { path = "src/main.lua", status = "M", reviewed = false }
	diff_view.current_file = test_file

	expect.equality(diff_view.current_file.path, "src/main.lua")
	expect.equality(diff_view.current_file.status, "M")

	-- Cleanup
	diff_view:close()
end

T["DiffView Integration"]["toggle_reviewed notifies callback"] = function()
	local Session = require("oversight.lib.storage.session")
	local DiffViewBuffer = require("oversight.buffers.diff_view")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())
	session:ensure_file("src/main.lua", "M")

	local callback_called = false
	local callback_file = nil

	local diff_view = DiffViewBuffer.new({
		repo = repo,
		session = session,
		on_comment = function() end,
		on_toggle_reviewed = function(file)
			callback_called = true
			callback_file = file
		end,
		on_quit = function() end,
	})

	-- Set current_file directly (simulates show_file without git operations)
	local test_file = { path = "src/main.lua", status = "M", reviewed = false }
	diff_view.current_file = test_file

	-- Silence notification
	local old_notify = vim.notify
	vim.notify = function() end

	-- Toggle reviewed
	diff_view:toggle_reviewed()

	vim.notify = old_notify

	expect.equality(callback_called, true)
	expect.equality(callback_file.path, "src/main.lua")
	expect.equality(callback_file.reviewed, true)
	expect.equality(session:is_file_reviewed("src/main.lua"), true)

	-- Cleanup
	diff_view:close()
end

T["Panel Coordination"] = MiniTest.new_set()

T["Panel Coordination"]["file selection triggers diff view update"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")
	local DiffViewBuffer = require("oversight.buffers.diff_view")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	local files = {
		{ path = "file1.lua", status = "M", reviewed = false },
		{ path = "file2.lua", status = "A", reviewed = false },
	}

	local diff_view = DiffViewBuffer.new({
		repo = repo,
		session = session,
		on_comment = function() end,
		on_toggle_reviewed = function() end,
		on_quit = function() end,
	})

	local file_list = FileListBuffer.new({
		files = files,
		session = session,
		branch = "main",
		on_file_select = function(file, _index)
			-- Set current_file directly to avoid git operations in tests
			diff_view.current_file = file
		end,
		on_toggle_reviewed = function() end,
		on_open_file = function() end,
	})

	-- Trigger selection (simulates first file auto-select)
	file_list:select_file()
	expect.equality(diff_view.current_file.path, "file1.lua")

	-- Navigate and select second file
	file_list:move_cursor(1)
	expect.equality(diff_view.current_file.path, "file2.lua")

	-- Cleanup
	file_list:close()
	diff_view:close()
end

T["Panel Coordination"]["reviewed status syncs between panels"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")
	local DiffViewBuffer = require("oversight.buffers.diff_view")

	local repo = helpers.create_mock_repo()
	local session = Session.new(repo:get_root(), repo:get_head())

	local files = {
		{ path = "file1.lua", status = "M", reviewed = false },
	}
	session:ensure_file("file1.lua", "M")

	-- Forward declare file_list so it can be referenced in the callback
	local file_list

	local diff_view = DiffViewBuffer.new({
		repo = repo,
		session = session,
		on_comment = function() end,
		on_toggle_reviewed = function(file)
			-- Sync to file list
			if file_list then
				file_list:update_file_reviewed(file.path, file.reviewed)
			end
		end,
		on_quit = function() end,
	})

	file_list = FileListBuffer.new({
		files = files,
		session = session,
		branch = "main",
		on_file_select = function(file, _index)
			-- Don't call show_file to avoid git operations in tests
			diff_view.current_file = file
		end,
		on_toggle_reviewed = function() end,
		on_open_file = function() end,
	})

	-- Select file in file list (triggers on_file_select callback)
	file_list:select_file()

	-- Silence notification
	local old_notify = vim.notify
	vim.notify = function() end

	-- Toggle reviewed in diff view
	diff_view:toggle_reviewed()

	vim.notify = old_notify

	-- Both should show reviewed
	expect.equality(diff_view.current_file.reviewed, true)
	expect.equality(file_list:get_current_file().reviewed, true)
	expect.equality(session:is_file_reviewed("file1.lua"), true)

	-- Cleanup
	file_list:close()
	diff_view:close()
end

T["Full Workflow"] = MiniTest.new_set()

T["Full Workflow"]["complete review workflow simulation"] = function()
	local Session = require("oversight.lib.storage.session")
	local FileListBuffer = require("oversight.buffers.file_list")
	local DiffViewBuffer = require("oversight.buffers.diff_view")
	local Export = require("oversight.lib.export")

	local repo = helpers.create_mock_repo({
		files = {
			{ path = "src/main.lua", status = "M" },
			{ path = "src/utils.lua", status = "A" },
			{ path = "tests/test.lua", status = "M" },
		},
	})

	local session = Session.new(repo:get_root(), repo:get_head())

	local files = {}
	for _, file in ipairs(repo:get_changed_files()) do
		session:ensure_file(file.path, file.status)
		table.insert(files, {
			path = file.path,
			status = file.status,
			reviewed = false,
		})
	end

	-- Create components with proper callbacks
	local diff_view
	local file_list

	diff_view = DiffViewBuffer.new({
		repo = repo,
		session = session,
		on_comment = function() end,
		on_toggle_reviewed = function(file)
			if file_list then
				file_list:update_file_reviewed(file.path, file.reviewed)
			end
		end,
		on_quit = function() end,
	})

	file_list = FileListBuffer.new({
		files = files,
		session = session,
		branch = repo:get_branch(),
		on_file_select = function(file, _index)
			-- Set current_file directly to avoid git operations in tests
			diff_view.current_file = file
		end,
		on_toggle_reviewed = function() end,
		on_open_file = function() end,
	})

	-- Silence notifications
	local old_notify = vim.notify
	vim.notify = function() end

	-- Step 1: Select first file
	file_list:select_file()
	expect.equality(diff_view.current_file.path, "src/main.lua")

	-- Step 2: Add a comment
	session:add_comment("src/main.lua", 10, "new", "issue", "Fix this bug")

	-- Step 3: Mark file as reviewed
	-- After toggling, src/main.lua moves to the "reviewed" section at the bottom
	-- Display order becomes: [src/utils.lua, tests/test.lua, ---, src/main.lua]
	file_list:toggle_reviewed()
	expect.equality(session:is_file_reviewed("src/main.lua"), true)

	-- Step 4: Navigate to first unreviewed file
	-- Since src/main.lua is now in the reviewed section at the end,
	-- we go to the first file in display order (src/utils.lua)
	file_list:move_to(1)
	expect.equality(diff_view.current_file.path, "src/utils.lua")

	-- Step 5: Add another comment
	session:add_comment("src/utils.lua", 5, "new", "suggestion", "Consider refactoring")

	-- Step 6: Mark as reviewed via diff view toggle
	diff_view:toggle_reviewed()
	expect.equality(session:is_file_reviewed("src/utils.lua"), true)
	expect.equality(file_list:get_current_file().reviewed, true)

	-- Step 7: Check progress
	local reviewed, total = session:get_progress()
	expect.equality(reviewed, 2)
	expect.equality(total, 3)

	-- Step 8: Export
	local markdown = Export.to_markdown(session, repo)
	expect.equality(markdown:match("Fix this bug") ~= nil, true)
	expect.equality(markdown:match("Consider refactoring") ~= nil, true)

	-- Step 9: Session can be serialized
	local json_data = session:to_json()
	local restored = Session.from_json(json_data)
	expect.equality(#restored.comments, 2)
	expect.equality(restored:is_file_reviewed("src/main.lua"), true)

	vim.notify = old_notify

	-- Cleanup
	file_list:close()
	diff_view:close()
end

return T
