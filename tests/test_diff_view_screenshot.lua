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
		local Session = require("tuicr.lib.storage.session")
		return Session.new(%q, "abc123def456")
	]],
		root
	)
end

---Create mock diff data based on actual diff_view/ui.lua changes
---This is a real-world diff with multiple hunks of type annotation changes
---@return string lua_code Lua code for mock diff
function mock_data.ui_lua_diff()
	-- This is based on the actual diff for lua/tuicr/buffers/diff_view/ui.lua
	-- Multiple hunks with @return Component -> @return table type changes
	return [[{
		path = "lua/tuicr/buffers/diff_view/ui.lua",
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
		require("tuicr").setup()
	]])

	-- Create components in child
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("tuicr.buffers.diff_view")
		local Session = require("tuicr.lib.storage.session")

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
		require("tuicr").setup()
	]])

	-- Create components with comments
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("tuicr.buffers.diff_view")
		local Session = require("tuicr.lib.storage.session")

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

T["DiffViewBuffer Screenshots"]["renders reviewed file (folded)"] = function()
	-- Load the plugin
	child.lua([[
		vim.cmd("set rtp+=.")
		require("tuicr").setup()
	]])

	-- Create components with file marked as reviewed
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("tuicr.buffers.diff_view")
		local Session = require("tuicr.lib.storage.session")

		-- Create mock repo and session
		local mock_repo = %s
		local session = Session.new(mock_repo:get_root(), mock_repo:get_head())
		session:ensure_file("src/example.lua", "M")
		session:set_file_reviewed("src/example.lua", true)

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

		-- Set current file as reviewed and render
		_G.diff_view.current_file = { path = "src/example.lua", status = "M", reviewed = true }
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
		require("tuicr").setup()
	]])

	-- This test uses actual diff data from lua/tuicr/buffers/diff_view/ui.lua
	-- to capture how multi-hunk type annotation changes render
	child.lua(string.format(
		[[
		local DiffViewBuffer = require("tuicr.buffers.diff_view")
		local Session = require("tuicr.lib.storage.session")

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
		_G.diff_view.file_diffs["lua/tuicr/buffers/diff_view/ui.lua"] = mock_diff

		-- Set current file and render
		_G.diff_view.current_file = { path = "lua/tuicr/buffers/diff_view/ui.lua", status = "M", reviewed = false }
		_G.diff_view:show()
	]],
		mock_data.repo_code("/tmp/test-repo"),
		mock_data.ui_lua_diff()
	))

	-- Wait for render
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

return T
