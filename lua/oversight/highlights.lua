-- Highlight group definitions for oversight
--
-- Every group LINKS to a standard Neovim highlight group rather than naming a
-- colour. Two reasons:
--
--   1. Hardcoded hex follows whoever wrote it, not the user. The previous
--      palette here was One Dark, so oversight rendered dark-theme greys and
--      pastels on top of whatever colorscheme the user actually had.
--   2. Links are resolved at draw time, so they track `:colorscheme` changes
--      for free. A concrete `fg` would survive a theme switch and go on
--      clashing until Neovim restarted.
--
-- All of these are applied to inline spans (see `Ui.text`), never to whole
-- lines, so the link targets are chosen from the fg-only groups — one carrying
-- a background (Folded, DiffText, Special) would paint a ragged block
-- mid-line.

local M = {}

--- Setup all highlight groups
function M.setup()
	local highlights = {
		-- Diff line highlights. These three DO span whole lines, so the
		-- background-carrying Diff* groups are correct here.
		OversightDiffAdd = { link = "DiffAdd" },
		OversightDiffDelete = { link = "DiffDelete" },
		OversightDiffChange = { link = "DiffChange" },
		OversightDiffContext = { link = "Normal" },

		-- Line numbers
		OversightLineNumber = { link = "LineNr" },
		OversightLineNumberCurrent = { link = "CursorLineNr" },

		-- File status indicators. Added/Changed/Removed are Neovim's own
		-- VCS-diff groups (`:h hl-Added`) — exactly this use, and fg-only.
		-- Rename and copy have no standard group, so they borrow two accents
		-- that stay distinct from those three in practice.
		OversightFileAdded = { link = "Added" },
		OversightFileModified = { link = "Changed" },
		OversightFileDeleted = { link = "Removed" },
		OversightFileRenamed = { link = "Keyword" },
		OversightFileCopied = { link = "Type" },

		-- Review status
		OversightReviewed = { link = "DiagnosticOk" },
		OversightPending = { link = "Comment" },

		-- Comment types. The Diagnostic* groups carry the right severity
		-- semantics already, and every colorscheme styles them.
		OversightCommentNote = { link = "DiagnosticInfo" },
		OversightCommentSuggestion = { link = "DiagnosticHint" },
		OversightCommentIssue = { link = "DiagnosticError" },
		OversightCommentPraise = { link = "DiagnosticOk" },

		-- UI elements
		OversightSeparator = { link = "NonText" },
		OversightHeader = { link = "Title" },
		OversightHunkHeader = { link = "PreProc" },
		OversightCursor = { link = "CursorLine" },

		-- File list
		OversightFileListSelected = { link = "Visual" },
		OversightFileListCurrent = { link = "CursorLine" },
	}

	for name, opts in pairs(highlights) do
		-- `default = true` is the API form of `hi default link`: a group the
		-- user has already defined is left alone, so overriding one of these in
		-- a colorscheme or init.lua sticks even when setup() runs afterwards.
		opts.default = true
		vim.api.nvim_set_hl(0, name, opts)
	end
end

return M
