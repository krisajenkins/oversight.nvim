-- Pure UI functions for the file list buffer

local Ui = require("tuicr.lib.ui")

local M = {}

---Create a file row component
---@param file File The file to render
---@param is_current boolean Whether this file is currently selected
---@return Component component The row component
local function create_file_row(file, is_current)
	local opts = {
		interactive = true,
		item = {
			path = file.path,
			status = file.status,
			reviewed = file.reviewed,
		},
	}

	-- Add pointer for current file
	local pointer = is_current and ">" or " "
	local pointer_hl = is_current and "TuicrCursor" or "Normal"

	-- Status and review indicators
	local review_icon = file.reviewed and "[x]" or "[ ]"
	local review_hl = file.reviewed and "TuicrReviewed" or "TuicrPending"
	local status_hl = Ui.get_status_highlight(file.status)

	return Ui.row({
		Ui.text(pointer, { highlight = pointer_hl }),
		Ui.text(review_icon, { highlight = review_hl }),
		Ui.text(" "),
		Ui.text(file.status, { highlight = status_hl }),
		Ui.text(" "),
		Ui.text(file.path, { highlight = is_current and "TuicrFileListCurrent" or "Normal" }),
	}, opts)
end

---Create the file list UI with two sections: unreviewed and reviewed
---@param unreviewed_files File[] List of unreviewed files
---@param reviewed_files File[] List of reviewed files
---@param current_path string|nil Path of the currently selected file
---@return Component[] components UI components
---@return number|nil selected_line Line number of selected file (1-indexed, relative to file list)
function M.create(unreviewed_files, reviewed_files, current_path)
	local components = {}
	local selected_line = nil
	local line = 0

	if #unreviewed_files == 0 and #reviewed_files == 0 then
		table.insert(components, Ui.text("No changes to review", { highlight = "Comment" }))
		return components, nil
	end

	-- Render unreviewed files
	for _, file in ipairs(unreviewed_files) do
		line = line + 1
		local is_current = file.path == current_path
		if is_current then
			selected_line = line
		end
		table.insert(components, create_file_row(file, is_current))
	end

	-- Add separator if both sections have files
	if #unreviewed_files > 0 and #reviewed_files > 0 then
		line = line + 1
		table.insert(components, Ui.text("─────────────────────────────────", { highlight = "Comment" }))
	end

	-- Render reviewed files
	for _, file in ipairs(reviewed_files) do
		line = line + 1
		local is_current = file.path == current_path
		if is_current then
			selected_line = line
		end
		table.insert(components, create_file_row(file, is_current))
	end

	return components, selected_line
end

---Create a header component showing review progress
---@param reviewed number Number of reviewed files
---@param total number Total number of files
---@param branch string|nil Current branch name
---@return Component component Header component
function M.create_header(reviewed, total, branch)
	local branch_text = branch and ("[" .. branch .. "]") or "[detached]"
	local progress_text = string.format("%d/%d reviewed", reviewed, total)

	return Ui.col({
		Ui.row({
			Ui.text("tuicr ", { highlight = "TuicrHeader" }),
			Ui.text(branch_text, { highlight = "Comment" }),
		}),
		Ui.text(progress_text, { highlight = "Comment" }),
		Ui.empty_line(),
	})
end

return M
