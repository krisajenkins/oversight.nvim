-- Highlight group definitions for tuicr

local M = {}

--- Setup all highlight groups
function M.setup()
	local highlights = {
		-- Diff line highlights
		TuicrDiffAdd = { link = "DiffAdd" },
		TuicrDiffDelete = { link = "DiffDelete" },
		TuicrDiffChange = { link = "DiffChange" },
		TuicrDiffContext = { link = "Normal" },

		-- Line numbers
		TuicrLineNumber = { link = "LineNr" },
		TuicrLineNumberCurrent = { link = "CursorLineNr" },

		-- File status indicators
		TuicrFileAdded = { fg = "#98c379" }, -- Green
		TuicrFileModified = { fg = "#e5c07b" }, -- Yellow
		TuicrFileDeleted = { fg = "#e06c75" }, -- Red
		TuicrFileRenamed = { fg = "#c678dd" }, -- Purple
		TuicrFileCopied = { fg = "#56b6c2" }, -- Cyan

		-- Review status
		TuicrReviewed = { fg = "#98c379" }, -- Green checkmark
		TuicrPending = { fg = "#abb2bf" }, -- Gray

		-- Comment types
		TuicrCommentNote = { fg = "#61afef" }, -- Blue
		TuicrCommentSuggestion = { fg = "#56b6c2" }, -- Cyan
		TuicrCommentIssue = { fg = "#e06c75" }, -- Red
		TuicrCommentPraise = { fg = "#98c379" }, -- Green

		-- UI elements
		TuicrSeparator = { fg = "#5c6370" }, -- Dim separator
		TuicrHeader = { fg = "#e5c07b", bold = true }, -- File headers
		TuicrHunkHeader = { fg = "#56b6c2" }, -- @@ hunk headers
		TuicrCursor = { link = "CursorLine" }, -- Current line indicator

		-- File list
		TuicrFileListSelected = { link = "Visual" },
		TuicrFileListCurrent = { link = "CursorLine" },
	}

	for name, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, name, opts)
	end
end

return M
