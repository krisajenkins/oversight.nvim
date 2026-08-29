-- Screenshot tests for the review mode diff.
--
-- These drive the whole of review mode against a real throwaway git repository,
-- rather than injecting data into DiffViewBuffer. They have to: the view no
-- longer holds any diff of its own to inject. It puts the file at the base
-- revision in one buffer and the working copy in the other, and everything you
-- can see — which lines are added, which are changed, where the filler goes —
-- is Neovim's own diff drawing it.
--
-- That makes the screenshots worth rather more than the old ones. They are the
-- only check that the two panes actually line up, including underneath a
-- comment, where a missing mirror block would show as the two sides sliding out
-- of step.

local child, child_set = require("tests.helpers.child")()
local expect = MiniTest.expect

local T = child_set()

-- A repository with one commit and every status on top of it.
local BASE =
	[=[local M = {}\n\nfunction M.greet(name)\n  return "Hello, " .. name\nend\n\nfunction M.farewell(name)\n  return "Goodbye, " .. name\nend\n\nreturn M\n]=]
local WORKING =
	[=[local M = {}\n\nfunction M.greet(name)\n  return "Hello there, " .. name\nend\n\nfunction M.farewell(name)\n  return "Goodbye, " .. name\nend\n\nfunction M.shout(text)\n  return text:upper()\nend\n\nreturn M\n]=]

local MAKE_REPO = require("tests.helpers.git_repo")({
	"mkdir -p src",
	"printf '" .. BASE .. "' > src/app.lua",
	"git add -A",
	"git commit --quiet -m init",
	"printf '" .. WORKING .. "' > src/app.lua",
	[=[printf 'local M = {}\n\nfunction M.enabled()\n  return true\nend\n\nreturn M\n' > src/new_feature.lua]=],
	[=[printf '\x00\x01\x02BINARY\xff\xfe\x00' > src/logo.bin]=],
	"git add -A",
})

---Open review mode on the throwaway repository, showing one file.
---@param path string File to select
---@param extra? string Lua source run after the file is shown, before the redraw
local function review(path, extra)
	child.lua(MAKE_REPO)
	child.lua(string.format(
		[[
		make_repo()

		-- 'diffopt' is global and the plugin deliberately leaves it alone, so a
		-- screenshot has to pin it or it renders whatever the machine happens to
		-- have. This is Neovim's own default.
		vim.o.diffopt = "internal,filler,closeoff"

		require("oversight").setup({ watch = false })
		_G.view = require("oversight.buffers.review").open()
		assert(_G.view, "review failed to open")

		for index, file in ipairs(_G.view.file_list.files) do
			if file.path == %q then
				_G.view.file_list:move_to(index)
			end
		end

		%s

		vim.cmd("redraw")
	]],
		path,
		extra or ""
	))
end

T["Review diff"] = MiniTest.new_set()

T["Review diff"]["renders a modified file as a native side-by-side diff"] = function()
	review("src/app.lua")

	expect.reference_screenshot(child.get_screenshot())
end

-- An added file has no content at HEAD at all, so the base pane is empty and
-- every line of the working copy is filler on the other side.
T["Review diff"]["renders an added file against an empty base"] = function()
	review("src/new_feature.lua")

	expect.reference_screenshot(child.get_screenshot())
end

T["Review diff"]["shows a notice instead of a diff for a binary file"] = function()
	review("src/logo.bin")

	expect.reference_screenshot(child.get_screenshot())
end

-- The one that matters. A comment is virtual lines, which Neovim's diff does
-- not count when it aligns the two windows, so each one is placed twice: the
-- text on its own side and an equal-height blank block at the counterpart line
-- on the other. Without the mirror the panes slide apart below the first
-- comment, and that is what this screenshot would show.
T["Review diff"]["keeps the panes aligned under comments on both sides"] = function()
	review(
		"src/app.lua",
		[[
		_G.view.session:add_comment("src/app.lua", 4, "new", "issue", "Too chatty")
		_G.view.session:add_comment("src/app.lua", 4, "old", "question", "Why did this change?")
		_G.view.session:add_comment("src/app.lua", 11, "new", "suggestion", "Worth a test")
		_G.view.diff_view:render()
	]]
	)

	expect.reference_screenshot(child.get_screenshot())
end

-- A file-level comment hangs off the last line, which is where the old renderer
-- put it. Above line 1 reads better but does not draw: there is no screen row
-- above the top of a window, so Neovim quietly omits virt_lines_above there.
T["Review diff"]["renders a file-level comment below both panes"] = function()
	review(
		"src/app.lua",
		[[
		_G.view.session:add_comment("src/app.lua", nil, nil, "suggestion", "Two lines\nof note")
		_G.view.diff_view:render()
	]]
	)

	expect.reference_screenshot(child.get_screenshot())
end

return T
