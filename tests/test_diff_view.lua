-- Tests for the review diff view.
--
-- The pure half checks what the view draws around Neovim's diff: the winbars,
-- and the virtual lines a comment becomes. The child half checks the one thing
-- that cannot be checked any other way — that the two panes are still aligned
-- once comments are in them.

local child, child_set = require("tests.helpers.child")()
local git_repo = require("tests.helpers.git_repo")
local DiffViewUI = require("oversight.buffers.diff_view.ui")

local T = MiniTest.new_set()
local expect = MiniTest.expect

-- ---------------------------------------------------------------------------
-- What the view draws around the diff
-- ---------------------------------------------------------------------------

T["Diff view UI"] = MiniTest.new_set()

---@param comment_type string
---@param text string
---@return Comment
local function comment(comment_type, text)
	return {
		id = "id",
		file = "src/app.lua",
		line = 1,
		side = "new",
		type = comment_type,
		text = text,
		created_at = "",
	}
end

---The text of each virtual line, with its chunks joined.
---@param virt_lines table[]
---@return string[]
local function texts(virt_lines)
	return vim.tbl_map(function(line)
		return table.concat(vim.tbl_map(function(chunk)
			return chunk[1]
		end, line))
	end, virt_lines)
end

T["Diff view UI"]["draws a comment as one virtual line per line of text"] = function()
	expect.equality(texts(DiffViewUI.comment_virt_lines(comment("issue", "Too chatty"))), {
		"  [ISSUE] Too chatty",
	})
end

-- Continuation lines are indented past the label, so a multi-line comment reads
-- as one block rather than as several unrelated notes.
T["Diff view UI"]["indents the continuation lines of a multi-line comment"] = function()
	expect.equality(texts(DiffViewUI.comment_virt_lines(comment("suggestion", "first\nsecond"))), {
		"  [SUGGESTION] first",
		"               second",
	})
end

T["Diff view UI"]["highlights every chunk by comment type"] = function()
	for _, case in ipairs({
		{ "issue", "OversightCommentIssue" },
		{ "question", "OversightCommentQuestion" },
		{ "suggestion", "OversightCommentSuggestion" },
	}) do
		local lines = DiffViewUI.comment_virt_lines(comment(case[1], "text"))
		for _, chunk in ipairs(lines[1]) do
			expect.equality(chunk[2], case[2])
		end
	end
end

-- The mirror has to be exactly as tall as what it mirrors, or the panes drift
-- by the difference.
T["Diff view UI"]["matches a comment's height with blank lines"] = function()
	local lines = DiffViewUI.comment_virt_lines(comment("issue", "one\ntwo\nthree"))

	expect.equality(#DiffViewUI.blank_virt_lines(#lines), 3)
	expect.equality(texts(DiffViewUI.blank_virt_lines(2)), { "", "" })
end

-- `%` introduces an item in a 'winbar', so a path containing one would swallow
-- the characters after it rather than displaying.
T["Diff view UI"]["escapes percent signs in a path"] = function()
	expect.equality(DiffViewUI.base_winbar("src/100%.lua"):find("src/100%%.lua", 1, true) ~= nil, true)
	expect.equality(DiffViewUI.working_winbar("src/100%.lua", "M", false):find("src/100%%.lua", 1, true) ~= nil, true)
end

T["Diff view UI"]["marks the working side as reviewed"] = function()
	expect.equality(DiffViewUI.working_winbar("a.lua", "M", false):find("✓", 1, true), nil)
	expect.equality(DiffViewUI.working_winbar("a.lua", "M", true):find("✓", 1, true) ~= nil, true)
end

-- ---------------------------------------------------------------------------
-- Alignment, in a real diff
-- ---------------------------------------------------------------------------

local MAKE_REPO = git_repo({
	"mkdir -p src",
	[[printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n' > src/app.lua]],
	"git add -A",
	"git commit --quiet -m init",
	-- A deletion, a change and an insertion, so the diff has filler on both
	-- sides and the counterpart of a line is not simply its own number.
	[[printf 'one\nTWO\nfour\nfive\nADDED\nALSO ADDED\nsix\nseven\neight\n' > src/app.lua]],
	"git add -A",
})

T["Diff view alignment"] = child_set({
	pre_case = function()
		child.lua(MAKE_REPO)
		child.lua([[
			make_repo()
			vim.o.diffopt = "internal,filler,closeoff"
			require("oversight").setup({ watch = false })
			_G.view = assert(require("oversight.buffers.review").open(), "review failed to open")
			vim.cmd("redraw")
		]])
	end,
})

---Every pair of lines Neovim has put on the same display row, one from each
---side, as the screen rows they actually occupy. Equal rows mean the panes are
---in step; the pairing itself is what `_display_rows` claims, so this checks the
---claim against what was drawn.
---@return table[] pairs Each { base_line, base_row, working_line, working_row }
local function aligned_rows()
	return child.lua_get([[(function()
		local dv = _G.view.diff_view
		local rows = dv:_display_rows()

		local working_at = {}
		for line, row in ipairs(rows.new) do
			working_at[row] = line
		end

		local out = {}
		for line, row in ipairs(rows.old) do
			local mate = working_at[row]
			if mate then
				table.insert(out, {
					line,
					vim.fn.screenpos(dv.old_win, line, 1).row,
					mate,
					vim.fn.screenpos(dv.new_win, mate, 1).row,
				})
			end
		end
		return out
	end)()]])
end

---@param rows table[]
---@return table[] drifted Pairs whose two screen rows disagree
local function drifted(rows)
	return vim.tbl_filter(function(pair)
		return pair[2] ~= pair[4]
	end, rows)
end

T["Diff view alignment"]["puts counterpart lines on the same screen row"] = function()
	local rows = aligned_rows()

	-- Guard against the assertion below passing vacuously.
	expect.equality(#rows > 5, true)
	expect.equality(drifted(rows), {})
end

-- The reason every comment is placed twice. Virtual lines are not counted by
-- Neovim's diff when it works out its filler, so a comment on one side alone
-- pushes that side down and nothing puts it back.
T["Diff view alignment"]["stays aligned under comments on both sides"] = function()
	child.lua([[
		_G.view.session:add_comment("src/app.lua", 2, "new", "issue", "shouty")
		_G.view.session:add_comment("src/app.lua", 2, "old", "question", "why?")
		_G.view.session:add_comment("src/app.lua", 5, "new", "suggestion", "two\nlines")
		_G.view.diff_view:render()
		vim.cmd("redraw")
	]])

	expect.equality(drifted(aligned_rows()), {})
end

-- A deleted line has no counterpart at all: its display row is filler on the
-- other side. The mirror falls back to the nearest line above, which puts the
-- blank block a row or two early — inside the hunk being commented on — and
-- both sides are back in step below it.
T["Diff view alignment"]["falls back to the nearest line above a one-sided line"] = function()
	-- Base line 3 ("three") is deleted, so nothing on the working side shares its
	-- display row. Line 2 is the nearest above.
	expect.equality(child.lua_get([[_G.view.diff_view:_counterpart("old", 3)]]), 2)
end

-- Without the mirror the panes come apart, which is what makes the mirror worth
-- its complexity. Placing the comment by hand, on one side only, is the closest
-- thing to a negative control.
T["Diff view alignment"]["would drift without the mirror"] = function()
	child.lua([[
		local dv = _G.view.diff_view
		local ns = vim.api.nvim_create_namespace("oversight_comments")
		vim.api.nvim_buf_set_extmark(dv.new:get_handle(), ns, 1, 0, {
			virt_lines = { { { "unmirrored", "Comment" } } },
		})
		vim.cmd("redraw")
	]])

	expect.equality(#drifted(aligned_rows()) > 0, true)
end

return T
