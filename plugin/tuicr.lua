-- tuicr plugin initialization
-- This file is automatically loaded by Neovim when the plugin is installed

-- Only load once
if vim.g.loaded_tuicr then
	return
end
vim.g.loaded_tuicr = 1

-- Re-apply highlights after colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("TuicrHighlights", { clear = true }),
	callback = function()
		require("tuicr.highlights").setup()
	end,
})
