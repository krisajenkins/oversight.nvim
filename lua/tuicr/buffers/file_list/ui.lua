-- Pure UI functions for the file list buffer

local Ui = require("tuicr.lib.ui")

local M = {}

---Create the file list UI
---@param files File[] List of files
---@param current_index number Currently selected file index (1-indexed)
---@return Component[] components UI components
function M.create(files, current_index)
	local components = {}

	if #files == 0 then
		table.insert(components, Ui.text("No changes to review", { highlight = "Comment" }))
		return components
	end

	for i, file in ipairs(files) do
		local is_current = i == current_index
		local opts = {
			interactive = true,
			item = {
				index = i,
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

		local row = Ui.row({
			Ui.text(pointer, { highlight = pointer_hl }),
			Ui.text(review_icon, { highlight = review_hl }),
			Ui.text(" "),
			Ui.text(file.status, { highlight = status_hl }),
			Ui.text(" "),
			Ui.text(file.path, { highlight = is_current and "TuicrFileListCurrent" or "Normal" }),
		}, opts)

		table.insert(components, row)
	end

	return components
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
