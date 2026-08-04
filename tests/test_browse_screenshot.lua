-- Screenshot tests for browse mode (FileTreeBuffer and FileViewBuffer).
--
-- file_tree is the largest module in the plugin and file_view is the third
-- largest, and between them they had no screenshot coverage at all — every
-- layout decision they make (indentation, the reviewed/unreviewed split, the
-- comment gutter) was only ever checked by eye.
--
-- Both buffers are constructed directly and fed data, rather than driven
-- through BrowseBuffer: that keeps the VCS out of the picture entirely, so a
-- screenshot only ever moves when the rendering does.

local child, child_set = require("tests.helpers.child")()
local expect = MiniTest.expect

local T = child_set()

-- A file set with enough nesting to show indentation, and enough breadth to
-- show directories sorting before files.
local FILES = [[{
	{ path = "README.md", status = "", reviewed = false },
	{ path = "lua/oversight/init.lua", status = "", reviewed = false },
	{ path = "lua/oversight/lib/buffer.lua", status = "", reviewed = false },
	{ path = "lua/oversight/lib/ui/init.lua", status = "", reviewed = false },
	{ path = "lua/oversight/lib/ui/renderer.lua", status = "", reviewed = false },
	{ path = "tests/test_ui.lua", status = "", reviewed = false },
}]]

local FILE_CONTENT = [[{
	"-- Example module",
	"local M = {}",
	"",
	"---Greet someone by name",
	"---@param name string",
	"---@return string greeting",
	"function M.greet(name)",
	"\treturn \"Hello, \" .. name",
	"end",
	"",
	"return M",
}]]

---Lua source that puts a FileTreeBuffer in `_G.file_tree` and shows it.
---@param files string Lua source for the file list
---@return string
local function build_tree(files)
	return string.format(
		[[
		local FileTreeBuffer = require("oversight.buffers.file_tree")
		local Session = require("oversight.lib.session")

		_G.session = Session.new("/tmp/test-repo", "abc123def456")
		_G.file_tree = FileTreeBuffer.new({
			files = %s,
			session = _G.session,
			branch = "main",
		})
		_G.file_tree:show()
	]],
		files
	)
end

---Lua source that puts a FileViewBuffer in `_G.file_view` showing one file.
---@param extra? string Extra source run after the buffer exists, before show_file
---@return string
local function build_view(extra)
	return string.format(
		[[
		local FileViewBuffer = require("oversight.buffers.file_view")
		local Session = require("oversight.lib.session")

		_G.session = Session.new("/tmp/test-repo", "abc123def456")
		_G.file_view = FileViewBuffer.new({
			-- read_file is the only backend method the view uses, and the cache
			-- below means it is never called. Kept honest rather than omitted.
			repo = { read_file = function() return nil end },
			session = _G.session,
		})
		_G.file_view:show()

		-- Inject the file contents rather than reading from disk, so the
		-- screenshot does not depend on a real file existing.
		_G.file_view.file_cache["src/example.lua"] = %s

		%s

		_G.file_view:show_file({ path = "src/example.lua", status = "", reviewed = false })
	]],
		FILE_CONTENT,
		extra or ""
	)
end

T["FileTreeBuffer Screenshots"] = MiniTest.new_set()

T["FileTreeBuffer Screenshots"]["renders a nested tree of unreviewed files"] = function()
	child.lua(build_tree(FILES))
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

-- Reviewed files move below a separator into their own tree, which is rebuilt
-- from scratch — so the two sections each carry their own directory rows.
T["FileTreeBuffer Screenshots"]["splits reviewed files below a separator"] = function()
	child.lua(build_tree(FILES))
	child.lua([[
		_G.file_tree:update_file_reviewed("lua/oversight/lib/buffer.lua", true)
		_G.file_tree:update_file_reviewed("README.md", true)
		vim.cmd('redraw')
	]])

	expect.reference_screenshot(child.get_screenshot())
end

T["FileTreeBuffer Screenshots"]["renders a collapsed directory"] = function()
	child.lua(build_tree(FILES))
	child.lua([[
		-- Directories default to expanded; collapsing one hides its whole subtree.
		_G.file_tree.expanded["lua/oversight/lib"] = false
		_G.file_tree:_update_visible_nodes()
		_G.file_tree:render()
		vim.cmd('redraw')
	]])

	expect.reference_screenshot(child.get_screenshot())
end

T["FileTreeBuffer Screenshots"]["renders an empty repository"] = function()
	child.lua(build_tree("{}"))
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

T["FileViewBuffer Screenshots"] = MiniTest.new_set()

T["FileViewBuffer Screenshots"]["renders file content with line numbers"] = function()
	child.lua(build_view())
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

-- One of each comment type, so the three highlight groups are all exercised in
-- a single reference.
T["FileViewBuffer Screenshots"]["renders inline comments of every type"] = function()
	child.lua(build_view([[
		_G.session:add_comment("src/example.lua", 2, "new", "question", "What owns this table?")
		_G.session:add_comment("src/example.lua", 7, "new", "issue", "No validation of `name`")
		_G.session:add_comment("src/example.lua", 8, "new", "suggestion", "Use string.format here")
	]]))
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

T["FileViewBuffer Screenshots"]["renders a file-level comment"] = function()
	child.lua(build_view([[
		_G.session:add_comment("src/example.lua", nil, nil, "question", "Whole-file question")
	]]))
	child.lua([[vim.cmd('redraw')]])

	expect.reference_screenshot(child.get_screenshot())
end

-- With no file selected the view is a placeholder, not an empty buffer.
T["FileViewBuffer Screenshots"]["renders the no-selection placeholder"] = function()
	child.lua([[
		local FileViewBuffer = require("oversight.buffers.file_view")
		local Session = require("oversight.lib.session")

		_G.file_view = FileViewBuffer.new({
			repo = { read_file = function() return nil end },
			session = Session.new("/tmp/test-repo", "abc123def456"),
		})
		_G.file_view:show()
		vim.cmd('redraw')
	]])

	expect.reference_screenshot(child.get_screenshot())
end

return T
