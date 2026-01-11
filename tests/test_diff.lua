-- Tests for diff parsing

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Diff"] = MiniTest.new_set()

T["Diff"]["parses unified diff"] = function()
	local Diff = require("oversight.lib.diff")

	local diff_lines = {
		"@@ -1,3 +1,4 @@",
		" unchanged",
		"-removed",
		"+added",
		"+another add",
		" context",
	}

	local hunks = Diff.parse_unified_diff(diff_lines)

	expect.equality(#hunks, 1)
	expect.equality(hunks[1].old_start, 1)
	expect.equality(hunks[1].old_count, 3)
	expect.equality(hunks[1].new_start, 1)
	expect.equality(hunks[1].new_count, 4)
	expect.equality(#hunks[1].lines, 5)
end

T["Diff"]["identifies line types correctly"] = function()
	local Diff = require("oversight.lib.diff")

	local diff_lines = {
		"@@ -1,3 +1,3 @@",
		" context",
		"-deleted",
		"+added",
	}

	local hunks = Diff.parse_unified_diff(diff_lines)
	local lines = hunks[1].lines

	expect.equality(lines[1].type, "context")
	expect.equality(lines[2].type, "delete")
	expect.equality(lines[3].type, "add")
end

T["Diff"]["tracks line numbers"] = function()
	local Diff = require("oversight.lib.diff")

	local diff_lines = {
		"@@ -10,2 +10,2 @@",
		" context",
		"-old line",
		"+new line",
	}

	local hunks = Diff.parse_unified_diff(diff_lines)
	local lines = hunks[1].lines

	-- Context line
	expect.equality(lines[1].line_no_old, 10)
	expect.equality(lines[1].line_no_new, 10)

	-- Deleted line
	expect.equality(lines[2].line_no_old, 11)
	expect.equality(lines[2].line_no_new, nil)

	-- Added line
	expect.equality(lines[3].line_no_old, nil)
	expect.equality(lines[3].line_no_new, 11)
end

T["Diff"]["converts to side-by-side"] = function()
	local Diff = require("oversight.lib.diff")

	local diff_lines = {
		"@@ -1,2 +1,2 @@",
		" same",
		"-old",
		"+new",
	}

	local hunks = Diff.parse_unified_diff(diff_lines)
	local side_by_side = Diff.to_side_by_side(hunks)

	-- Should have: hunk header, context, paired change
	expect.equality(#side_by_side, 3)

	-- First is hunk header
	expect.equality(side_by_side[1].type, "hunk_header")

	-- Second is context
	expect.equality(side_by_side[2].type, "context")
	expect.equality(side_by_side[2].content_old, "same")
	expect.equality(side_by_side[2].content_new, "same")

	-- Third is paired change
	expect.equality(side_by_side[3].type, "change")
	expect.equality(side_by_side[3].content_old, "old")
	expect.equality(side_by_side[3].content_new, "new")
end

T["Diff"]["handles multiple hunks"] = function()
	local Diff = require("oversight.lib.diff")

	local diff_lines = {
		"@@ -1,1 +1,1 @@",
		"-old1",
		"+new1",
		"@@ -10,1 +10,1 @@",
		"-old2",
		"+new2",
	}

	local hunks = Diff.parse_unified_diff(diff_lines)

	expect.equality(#hunks, 2)
	expect.equality(hunks[1].old_start, 1)
	expect.equality(hunks[2].old_start, 10)
end

T["Diff"]["handles only additions"] = function()
	local Diff = require("oversight.lib.diff")

	local diff_lines = {
		"@@ -0,0 +1,2 @@",
		"+line1",
		"+line2",
	}

	local hunks = Diff.parse_unified_diff(diff_lines)
	local side_by_side = Diff.to_side_by_side(hunks)

	-- Hunk header + 2 additions
	expect.equality(#side_by_side, 3)
	expect.equality(side_by_side[2].type, "add")
	expect.equality(side_by_side[3].type, "add")
end

T["Diff"]["handles only deletions"] = function()
	local Diff = require("oversight.lib.diff")

	local diff_lines = {
		"@@ -1,2 +0,0 @@",
		"-line1",
		"-line2",
	}

	local hunks = Diff.parse_unified_diff(diff_lines)
	local side_by_side = Diff.to_side_by_side(hunks)

	-- Hunk header + 2 deletions
	expect.equality(#side_by_side, 3)
	expect.equality(side_by_side[2].type, "delete")
	expect.equality(side_by_side[3].type, "delete")
end

return T
