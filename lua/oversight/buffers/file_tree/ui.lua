-- Pure UI functions for the file tree buffer (browse mode)

local Ui = require("oversight.lib.ui")

local M = {}

---Create a directory node row
---@param name string Directory name
---@param depth number Indentation depth
---@param expanded boolean Whether the directory is expanded
---@param is_current boolean Whether this node is currently selected
---@return Component component Directory row component
function M.create_dir_row(name, depth, expanded, is_current)
	local indent = string.rep("  ", depth)
	local marker = expanded and "▾" or "▸"
	local pointer = is_current and ">" or " "
	local pointer_hl = is_current and "OversightCursor" or "Normal"

	return Ui.row({
		Ui.text(pointer, { highlight = pointer_hl }),
		Ui.text(indent .. marker .. " " .. name .. "/", { highlight = "OversightHeader" }),
	}, {
		interactive = true,
		item = {
			type = "dir",
			name = name,
		},
	})
end

---Create a file node row
---@param name string File name
---@param depth number Indentation depth
---@param reviewed boolean Whether the file is reviewed
---@param is_current boolean Whether this node is currently selected
---@return Component component File row component
function M.create_file_row(name, depth, reviewed, is_current)
	local indent = string.rep("  ", depth)
	local review_icon = reviewed and "[x]" or "[ ]"
	local review_hl = reviewed and "OversightReviewed" or "OversightPending"
	local pointer = is_current and ">" or " "
	local pointer_hl = is_current and "OversightCursor" or "Normal"

	return Ui.row({
		Ui.text(pointer, { highlight = pointer_hl }),
		Ui.text(indent .. "  ", {}),
		Ui.text(review_icon, { highlight = review_hl }),
		Ui.text(" " .. name, { highlight = is_current and "OversightFileListCurrent" or "Normal" }),
	}, {
		interactive = true,
		item = {
			type = "file",
			name = name,
		},
	})
end

---Create a header component showing browse mode info
---@param reviewed number Number of reviewed files
---@param total number Total number of files
---@param branch string|nil Current branch name
---@return Component component Header component
function M.create_header(reviewed, total, branch)
	local branch_text = branch and ("[" .. branch .. "]") or "[detached]"
	local progress_text = string.format("%d/%d reviewed", reviewed, total)

	return Ui.col({
		Ui.row({
			Ui.text("oversight ", { highlight = "OversightHeader" }),
			Ui.text(branch_text, { highlight = "Comment" }),
		}),
		Ui.text(progress_text, { highlight = "Comment" }),
		Ui.empty_line(),
	})
end

---Create a separator between unreviewed and reviewed sections
---@return Component component Separator component
function M.create_separator()
	return Ui.text(
		"─────────────────────────────────",
		{ highlight = "Comment" }
	)
end

return M
