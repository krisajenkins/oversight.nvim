-- Screenshot tests for DiffViewBuffer
-- Tests visual rendering of diff views with various content types

local child = MiniTest.new_child_neovim()
local expect = MiniTest.expect

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			-- Set consistent dimensions for reproducible screenshots
			child.o.lines = 30
			child.o.columns = 100
		end,
		post_once = child.stop,
	},
})

-- Mock data helpers
local mock_data = {}

---Create a mock repository
---@param root string Repository root path
---@return string lua_code Lua code to create mock repo
function mock_data.repo_code(root)
	return string.format(
		[[{
		get_root = function() return %q end,
		get_branch = function() return "main" end,
		get_head = function() return "abc123def456" end,
	}]],
		root
	)
end

---Create mock diff data for a standard modified file
---@return string lua_code Lua code for mock diff
function mock_data.standard_diff()
	return [[{
		path = "src/example.lua",
		old_path = nil,
		status = "M",
		is_binary = false,
		hunks = {
			{
				header = "@@ -1,7 +1,9 @@",
				old_start = 1,
				old_count = 7,
				new_start = 1,
				new_count = 9,
				lines = {
					{ line_no_old = 1, line_no_new = 1, content_old = "-- Example module", content_new = "-- Example module", type = "context" },
					{ line_no_old = 2, line_no_new = 2, content_old = "local M = {}", content_new = "local M = {}", type = "context" },
					{ line_no_old = 3, line_no_new = nil, content_old = "-- Old comment", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 3, content_old = "", content_new = "-- New improved comment", type = "add" },
					{ line_no_old = nil, line_no_new = 4, content_old = "", content_new = "-- Extra documentation", type = "add" },
					{ line_no_old = 4, line_no_new = 5, content_old = "function M.hello()", content_new = "function M.hello()", type = "context" },
					{ line_no_old = 5, line_no_new = nil, content_old = "  print('hello')", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 6, content_old = "", content_new = "  print('Hello, World!')", type = "add" },
					{ line_no_old = 6, line_no_new = 7, content_old = "end", content_new = "end", type = "context" },
					{ line_no_old = 7, line_no_new = 8, content_old = "return M", content_new = "return M", type = "context" },
				},
			},
		},
	}]]
end

---Create mock session code
---@param root string Repository root
---@return string lua_code
function mock_data.session_code(root)
	return string.format(
		[[
		local Session = require("oversight.lib.storage.session")
		return Session.new(%q, "abc123def456")
	]],
		root
	)
end

---Create mock diff data based on comment/init.lua changes
---This diff has multiple hunks with pure additions (no corresponding deletes)
---which can expose column alignment issues in the side-by-side view
---@return string lua_code Lua code for mock diff
function mock_data.comment_init_diff()
	return [[{
		path = "lua/oversight/buffers/comment/init.lua",
		old_path = nil,
		status = "M",
		is_binary = false,
		hunks = {
			{
				header = "@@ -2,6 +2,7 @@",
				old_start = 2,
				old_count = 6,
				new_start = 2,
				new_count = 7,
				lines = {
					{ line_no_old = 2, line_no_new = 2, content_old = "", content_new = "", type = "context" },
					{ line_no_old = 3, line_no_new = 3, content_old = "---@class CommentInputOpts", content_new = "---@class CommentInputOpts", type = "context" },
					{ line_no_old = 4, line_no_new = 4, content_old = "---@field context CommentContext Comment context (file, line, side)", content_new = "---@field context CommentContext Comment context (file, line, side)", type = "context" },
					{ line_no_old = nil, line_no_new = 5, content_old = "", content_new = "---@field existing_comment? Comment Optional existing comment for editing", type = "add" },
					{ line_no_old = 5, line_no_new = 6, content_old = "---@field on_submit? fun(comment: CommentData): nil Callback when comment is submitted", content_new = "---@field on_submit? fun(comment: CommentData): nil Callback when comment is submitted", type = "context" },
					{ line_no_old = 6, line_no_new = 7, content_old = "---@field on_cancel? fun(): nil Callback when input is cancelled", content_new = "---@field on_cancel? fun(): nil Callback when input is cancelled", type = "context" },
				},
			},
			{
				header = "@@ -10,6 +11,7 @@",
				old_start = 10,
				old_count = 6,
				new_start = 11,
				new_count = 7,
				lines = {
					{ line_no_old = 10, line_no_new = 11, content_old = "---@field win number Window handle", content_new = "---@field win number Window handle", type = "context" },
					{ line_no_old = 11, line_no_new = 12, content_old = "---@field context CommentContext Comment context (file, line, side)", content_new = "---@field context CommentContext Comment context (file, line, side)", type = "context" },
					{ line_no_old = 12, line_no_new = 13, content_old = '---@field comment_type "note"|"suggestion"|"issue"|"praise" Current comment type', content_new = '---@field comment_type "note"|"suggestion"|"issue"|"praise" Current comment type', type = "context" },
					{ line_no_old = nil, line_no_new = 14, content_old = "", content_new = "---@field existing_comment? Comment Optional existing comment being edited", type = "add" },
					{ line_no_old = 13, line_no_new = 15, content_old = "---@field on_submit? fun(comment: CommentData): nil Callback when comment is submitted", content_new = "---@field on_submit? fun(comment: CommentData): nil Callback when comment is submitted", type = "context" },
					{ line_no_old = 14, line_no_new = 16, content_old = "---@field on_cancel? fun(): nil Callback when input is cancelled", content_new = "---@field on_cancel? fun(): nil Callback when input is cancelled", type = "context" },
				},
			},
			{
				header = "@@ -21,9 +23,11 @@",
				old_start = 21,
				old_count = 9,
				new_start = 23,
				new_count = 11,
				lines = {
					{ line_no_old = 21, line_no_new = 23, content_old = "---@param opts CommentInputOpts Options", content_new = "---@param opts CommentInputOpts Options", type = "context" },
					{ line_no_old = 22, line_no_new = 24, content_old = "---@return CommentInput instance", content_new = "---@return CommentInput instance", type = "context" },
					{ line_no_old = 23, line_no_new = 25, content_old = "function CommentInput.new(opts)", content_new = "function CommentInput.new(opts)", type = "context" },
					{ line_no_old = nil, line_no_new = 26, content_old = "", content_new = "\tlocal existing = opts.existing_comment", type = "add" },
					{ line_no_old = 24, line_no_new = 27, content_old = "\tlocal instance = setmetatable({", content_new = "\tlocal instance = setmetatable({", type = "context" },
					{ line_no_old = 25, line_no_new = 28, content_old = "\t\tcontext = opts.context,", content_new = "\t\tcontext = opts.context,", type = "context" },
					{ line_no_old = 26, line_no_new = nil, content_old = '\t\tcomment_type = "note",', content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 29, content_old = "", content_new = "\t\tcomment_type = existing and existing.type or \"note\",", type = "add" },
					{ line_no_old = nil, line_no_new = 30, content_old = "", content_new = "\t\texisting_comment = existing,", type = "add" },
					{ line_no_old = 27, line_no_new = 31, content_old = "\t\ton_submit = opts.on_submit,", content_new = "\t\ton_submit = opts.on_submit,", type = "context" },
					{ line_no_old = 28, line_no_new = 32, content_old = "\t\ton_cancel = opts.on_cancel,", content_new = "\t\ton_cancel = opts.on_cancel,", type = "context" },
				},
			},
			{
				header = "@@ -49,6 +53,7 @@",
				old_start = 49,
				old_count = 6,
				new_start = 53,
				new_count = 7,
				lines = {
					{ line_no_old = 49, line_no_new = 53, content_old = "\tlocal col = math.floor((vim.o.columns - width) / 2)", content_new = "\tlocal col = math.floor((vim.o.columns - width) / 2)", type = "context" },
					{ line_no_old = 50, line_no_new = 54, content_old = "", content_new = "", type = "context" },
					{ line_no_old = 51, line_no_new = 55, content_old = "\t-- Create window", content_new = "\t-- Create window", type = "context" },
					{ line_no_old = nil, line_no_new = 56, content_old = "", content_new = '\tlocal title = self.existing_comment and " Edit Comment " or " Add Comment "', type = "add" },
					{ line_no_old = 52, line_no_new = 57, content_old = "\tself.win = vim.api.nvim_open_win(self.buf, true, {", content_new = "\tself.win = vim.api.nvim_open_win(self.buf, true, {", type = "context" },
					{ line_no_old = 53, line_no_new = 58, content_old = '\t\trelative = "editor",', content_new = '\t\trelative = "editor",', type = "context" },
				},
			},
			{
				header = "@@ -57,7 +62,7 @@",
				old_start = 57,
				old_count = 7,
				new_start = 62,
				new_count = 7,
				lines = {
					{ line_no_old = 57, line_no_new = 62, content_old = "\t\tcol = col,", content_new = "\t\tcol = col,", type = "context" },
					{ line_no_old = 58, line_no_new = 63, content_old = '\t\tstyle = "minimal",', content_new = '\t\tstyle = "minimal",', type = "context" },
					{ line_no_old = 59, line_no_new = 64, content_old = '\t\tborder = "rounded",', content_new = '\t\tborder = "rounded",', type = "context" },
					{ line_no_old = 60, line_no_new = nil, content_old = '\t\ttitle = " Add Comment ",', content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 65, content_old = "", content_new = "\t\ttitle = title,", type = "add" },
					{ line_no_old = 61, line_no_new = 66, content_old = '\t\ttitle_pos = "center",', content_new = '\t\ttitle_pos = "center",', type = "context" },
					{ line_no_old = 62, line_no_new = 67, content_old = "\t})", content_new = "\t})", type = "context" },
					{ line_no_old = 63, line_no_new = 68, content_old = "", content_new = "", type = "context" },
				},
			},
		},
	}]]
end

---Create mock diff data based on actual diff_view/ui.lua changes
---This is a real-world diff with multiple hunks of type annotation changes
---@return string lua_code Lua code for mock diff
function mock_data.ui_lua_diff()
	-- This is based on the actual diff for lua/oversight/buffers/diff_view/ui.lua
	-- Multiple hunks with @return Component -> @return table type changes
	return [[{
		path = "lua/oversight/buffers/diff_view/ui.lua",
		old_path = nil,
		status = "M",
		is_binary = false,
		hunks = {
			{
				header = "@@ -42,7 +42,7 @@",
				old_start = 42,
				old_count = 7,
				new_start = 42,
				new_count = 7,
				lines = {
					{ line_no_old = 42, line_no_new = 42, content_old = "---@param path string File path", content_new = "---@param path string File path", type = "context" },
					{ line_no_old = 43, line_no_new = 43, content_old = "---@param status string Git status", content_new = "---@param status string Git status", type = "context" },
					{ line_no_old = 44, line_no_new = 44, content_old = "---@param reviewed boolean Whether file has been reviewed", content_new = "---@param reviewed boolean Whether file has been reviewed", type = "context" },
					{ line_no_old = 45, line_no_new = nil, content_old = "---@return Component component File header component", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 45, content_old = "", content_new = "---@return table component File header component", type = "add" },
					{ line_no_old = 46, line_no_new = 46, content_old = "function M.create_file_header(path, status, reviewed)", content_new = "function M.create_file_header(path, status, reviewed)", type = "context" },
					{ line_no_old = 47, line_no_new = 47, content_old = "\tlocal status_hl = Ui.get_status_highlight(status)", content_new = "\tlocal status_hl = Ui.get_status_highlight(status)", type = "context" },
					{ line_no_old = 48, line_no_new = 48, content_old = "\tlocal reviewed_mark = reviewed and \"✓\" or \" \"", content_new = "\tlocal reviewed_mark = reviewed and \"✓\" or \" \"", type = "context" },
				},
			},
			{
				header = "@@ -62,10 +62,10 @@",
				old_start = 62,
				old_count = 10,
				new_start = 62,
				new_count = 10,
				lines = {
					{ line_no_old = 62, line_no_new = 62, content_old = "end", content_new = "end", type = "context" },
					{ line_no_old = 63, line_no_new = 63, content_old = "", content_new = "", type = "context" },
					{ line_no_old = 64, line_no_new = 64, content_old = "---Create side-by-side diff line component", content_new = "---Create side-by-side diff line component", type = "context" },
					{ line_no_old = 65, line_no_new = nil, content_old = "---@param line DiffLine Diff line data", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 65, content_old = "", content_new = "---@param line table DiffLine {line_no_old, line_no_new, content_old, content_new, type}", type = "add" },
					{ line_no_old = 66, line_no_new = 66, content_old = "---@param col_width number Width for each content column", content_new = "---@param col_width number Width for each content column", type = "context" },
					{ line_no_old = 67, line_no_new = nil, content_old = "---@param opts? ComponentOptions Additional options (interactive, item)", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 67, content_old = "", content_new = "---@param opts? table Additional options (interactive, item)", type = "add" },
					{ line_no_old = 68, line_no_new = nil, content_old = "---@return Component component Diff line component", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 68, content_old = "", content_new = "---@return table component Diff line component", type = "add" },
					{ line_no_old = 69, line_no_new = 69, content_old = "function M.create_diff_line(line, col_width, opts)", content_new = "function M.create_diff_line(line, col_width, opts)", type = "context" },
					{ line_no_old = 70, line_no_new = 70, content_old = "\topts = opts or {}", content_new = "\topts = opts or {}", type = "context" },
					{ line_no_old = 71, line_no_new = 71, content_old = "", content_new = "", type = "context" },
				},
			},
			{
				header = "@@ -102,7 +102,7 @@",
				old_start = 102,
				old_count = 7,
				new_start = 102,
				new_count = 7,
				lines = {
					{ line_no_old = 102, line_no_new = 102, content_old = "end", content_new = "end", type = "context" },
					{ line_no_old = 103, line_no_new = 103, content_old = "", content_new = "", type = "context" },
					{ line_no_old = 104, line_no_new = 104, content_old = "---Create binary file notice", content_new = "---Create binary file notice", type = "context" },
					{ line_no_old = 105, line_no_new = nil, content_old = "---@param path string File path", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 105, content_old = "", content_new = "---@param path string File path", type = "add" },
					{ line_no_old = 106, line_no_new = nil, content_old = "---@return Component component Binary notice component", content_new = "", type = "delete" },
					{ line_no_old = nil, line_no_new = 106, content_old = "", content_new = "---@return table component Binary notice component", type = "add" },
					{ line_no_old = 107, line_no_new = 107, content_old = "function M.create_binary_notice(path)", content_new = "function M.create_binary_notice(path)", type = "context" },
					{ line_no_old = 108, line_no_new = 108, content_old = "\treturn Ui.col({", content_new = "\treturn Ui.col({", type = "context" },
					{ line_no_old = 109, line_no_new = 109, content_old = "\t\tUi.empty_line(),", content_new = "\t\tUi.empty_line(),", type = "context" },
				},
			},
		},
	}]]
end

T["DiffViewBuffer Screenshots"] = MiniTest.new_set()

T["DiffViewBuffer Screenshots"]["renders standard diff with adds, deletes, context"] = function()
	-- Load the plugin
	child.lua([[
		vim.cmd("set rtp+=.")
		require("oversight").setup()
	]])

	-- Create components in child
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("oversight.buffers.diff_view")
		local Session = require("oversight.lib.storage.session")

		-- Create mock repo and session
		local mock_repo = %s
		local session = Session.new(mock_repo:get_root(), mock_repo:get_head())

		-- Create diff view buffer
		_G.diff_view = DiffViewBuffer.new({
			repo = mock_repo,
			session = session,
			on_comment = function() end,
			on_toggle_reviewed = function() end,
			on_quit = function() end,
		})

		-- Inject mock diff data directly (bypasses git CLI)
		local mock_diff = %s
		_G.diff_view.file_diffs["src/example.lua"] = mock_diff

		-- Set current file and render
		_G.diff_view.current_file = { path = "src/example.lua", status = "M", reviewed = false }
		_G.diff_view:show()
	]],
		mock_data.repo_code("/tmp/test-repo"),
		mock_data.standard_diff()
	))

	-- Wait for render
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

T["DiffViewBuffer Screenshots"]["renders diff with line comments"] = function()
	-- Load the plugin
	child.lua([[
		vim.cmd("set rtp+=.")
		require("oversight").setup()
	]])

	-- Create components with comments
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("oversight.buffers.diff_view")
		local Session = require("oversight.lib.storage.session")

		-- Create mock repo and session
		local mock_repo = %s
		local session = Session.new(mock_repo:get_root(), mock_repo:get_head())

		-- Add comments to the session
		session:add_comment("src/example.lua", 3, "new", "issue", "This comment is unclear")
		session:add_comment("src/example.lua", 6, "new", "suggestion", "Consider using string.format here")

		-- Create diff view buffer
		_G.diff_view = DiffViewBuffer.new({
			repo = mock_repo,
			session = session,
			on_comment = function() end,
			on_toggle_reviewed = function() end,
			on_quit = function() end,
		})

		-- Inject mock diff data directly
		local mock_diff = %s
		_G.diff_view.file_diffs["src/example.lua"] = mock_diff

		-- Set current file and render
		_G.diff_view.current_file = { path = "src/example.lua", status = "M", reviewed = false }
		_G.diff_view:show()
	]],
		mock_data.repo_code("/tmp/test-repo"),
		mock_data.standard_diff()
	))

	-- Wait for render
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

T["DiffViewBuffer Screenshots"]["renders real diff_view/ui.lua changes"] = function()
	-- Load the plugin
	child.lua([[
		vim.cmd("set rtp+=.")
		require("oversight").setup()
	]])

	-- This test uses actual diff data from lua/oversight/buffers/diff_view/ui.lua
	-- to capture how multi-hunk type annotation changes render
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("oversight.buffers.diff_view")
		local Session = require("oversight.lib.storage.session")

		-- Create mock repo and session
		local mock_repo = %s
		local session = Session.new(mock_repo:get_root(), mock_repo:get_head())

		-- Create diff view buffer
		_G.diff_view = DiffViewBuffer.new({
			repo = mock_repo,
			session = session,
			on_comment = function() end,
			on_toggle_reviewed = function() end,
			on_quit = function() end,
		})

		-- Inject mock diff data (based on real diff_view/ui.lua changes)
		local mock_diff = %s
		_G.diff_view.file_diffs["lua/oversight/buffers/diff_view/ui.lua"] = mock_diff

		-- Set current file and render
		_G.diff_view.current_file = { path = "lua/oversight/buffers/diff_view/ui.lua", status = "M", reviewed = false }
		_G.diff_view:show()
	]],
		mock_data.repo_code("/tmp/test-repo"),
		mock_data.ui_lua_diff()
	))

	-- Wait for render
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

T["DiffViewBuffer Screenshots"]["renders comment/init.lua diff with pure additions"] = function()
	-- Load the plugin
	child.lua([[
		vim.cmd("set rtp+=.")
		require("oversight").setup()
	]])

	-- This test uses diff data from lua/oversight/buffers/comment/init.lua
	-- which has hunks with pure additions (no corresponding deletes)
	-- that can expose column alignment issues
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("oversight.buffers.diff_view")
		local Session = require("oversight.lib.storage.session")

		-- Create mock repo and session
		local mock_repo = %s
		local session = Session.new(mock_repo:get_root(), mock_repo:get_head())

		-- Create diff view buffer
		_G.diff_view = DiffViewBuffer.new({
			repo = mock_repo,
			session = session,
			on_comment = function() end,
			on_toggle_reviewed = function() end,
			on_quit = function() end,
		})

		-- Inject mock diff data (based on comment/init.lua changes)
		local mock_diff = %s
		_G.diff_view.file_diffs["lua/oversight/buffers/comment/init.lua"] = mock_diff

		-- Set current file and render
		_G.diff_view.current_file = { path = "lua/oversight/buffers/comment/init.lua", status = "M", reviewed = false }
		_G.diff_view:show()
	]],
		mock_data.repo_code("/tmp/test-repo"),
		mock_data.comment_init_diff()
	))

	-- Wait for render
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

return T
