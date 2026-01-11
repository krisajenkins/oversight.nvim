-- Highlight group definitions for oversight

local M = {}

--- Setup all highlight groups
function M.setup()
	local highlights = {
		-- Diff line highlights
		OversightDiffAdd = { link = "DiffAdd" },
		OversightDiffDelete = { link = "DiffDelete" },
		OversightDiffChange = { link = "DiffChange" },
		OversightDiffContext = { link = "Normal" },

		-- Line numbers
		OversightLineNumber = { link = "LineNr" },
		OversightLineNumberCurrent = { link = "CursorLineNr" },

		-- File status indicators
		OversightFileAdded = { fg = "#98c379" }, -- Green
		OversightFileModified = { fg = "#e5c07b" }, -- Yellow
		OversightFileDeleted = { fg = "#e06c75" }, -- Red
		OversightFileRenamed = { fg = "#c678dd" }, -- Purple
		OversightFileCopied = { fg = "#56b6c2" }, -- Cyan

		-- Review status
		OversightReviewed = { fg = "#98c379" }, -- Green checkmark
		OversightPending = { fg = "#abb2bf" }, -- Gray

		-- Comment types
		OversightCommentNote = { fg = "#61afef" }, -- Blue
		OversightCommentSuggestion = { fg = "#56b6c2" }, -- Cyan
		OversightCommentIssue = { fg = "#e06c75" }, -- Red
		OversightCommentPraise = { fg = "#98c379" }, -- Green

		-- UI elements
		OversightSeparator = { fg = "#5c6370" }, -- Dim separator
		OversightHeader = { fg = "#e5c07b", bold = true }, -- File headers
		OversightHunkHeader = { fg = "#56b6c2" }, -- @@ hunk headers
		OversightCursor = { link = "CursorLine" }, -- Current line indicator

		-- File list
		OversightFileListSelected = { link = "Visual" },
		OversightFileListCurrent = { link = "CursorLine" },
	}

	for name, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, name, opts)
	end
end

return M
