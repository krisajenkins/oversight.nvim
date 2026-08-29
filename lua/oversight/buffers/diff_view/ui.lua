-- Pure UI functions for the diff view.
--
-- There is no diff rendering here any more: Neovim's own diff draws the two
-- panes, and this is what surrounds them — the winbar over each side, and the
-- virtual lines a comment becomes.

local Ui = require("oversight.lib.ui")

local M = {}

---Escape a string for use in a 'winbar', where `%` introduces an item.
---A path containing one would otherwise be read as a format specifier and
---silently swallow the characters after it.
---@param text string
---@return string escaped
local function escape(text)
	return (text:gsub("%%", "%%%%"))
end

---Wrap text in a winbar highlight group.
---@param group string Highlight group name
---@param text string Already-escaped text
---@return string item
local function hl(group, text)
	return "%#" .. group .. "#" .. text .. "%*"
end

---The winbar over the base side.
---@param path string The path the content had at the base revision
---@return string winbar
function M.base_winbar(path)
	return " " .. hl("OversightHeader", escape(path)) .. " " .. hl("OversightSeparator", "(base)")
end

---The winbar over the working-copy side.
---@param path string File path
---@param status string VCS status (A, M, D, R, C)
---@param reviewed boolean Whether the file has been marked reviewed
---@return string winbar
function M.working_winbar(path, status, reviewed)
	local mark = reviewed and "✓" or " "
	local mark_group = reviewed and "OversightReviewed" or "OversightSeparator"

	return " "
		.. hl(mark_group, mark)
		.. " "
		.. hl("OversightHeader", escape(path))
		.. " "
		.. hl("OversightSeparator", "(")
		.. hl(Ui.get_status_highlight(status), escape(status))
		.. hl("OversightSeparator", ")")
end

---The virtual lines a comment is drawn as, in the form
---`nvim_buf_set_extmark`'s `virt_lines` wants: a list of lines, each a list of
---[text, highlight] chunks.
---
---Comment text may span several lines; continuation lines are indented past the
---type label so the block reads as one thing.
---@param comment Comment
---@return table[] virt_lines
function M.comment_virt_lines(comment)
	local group, label = Ui.get_comment_type_display(comment.type)
	local indent = "  "
	local continuation = indent .. string.rep(" ", vim.fn.strdisplaywidth(label) + 1)

	local lines = {}
	for text in vim.gsplit(comment.text or "", "\n", { plain = true }) do
		if #lines == 0 then
			table.insert(lines, { { indent .. label .. " ", group }, { text, group } })
		else
			table.insert(lines, { { continuation .. text, group } })
		end
	end
	return lines
end

---A block of blank virtual lines, the mirror of a comment on the other side.
---
---Neovim's diff aligns the two windows with filler lines of its own and does
---not count `virt_lines`, so a comment rendered on one side alone pushes
---everything below it down by its own height and the panes drift apart. An
---equal-height blank block at the counterpart line puts that back.
---@param height number Number of blank lines
---@return table[] virt_lines
function M.blank_virt_lines(height)
	local lines = {}
	for _ = 1, height do
		table.insert(lines, { { "", "NonText" } })
	end
	return lines
end

---What to show instead of a diff.
---@param message string
---@param detail? string
---@return string[] lines
function M.notice(message, detail)
	local lines = { message }
	if detail then
		table.insert(lines, detail)
	end
	return lines
end

return M
