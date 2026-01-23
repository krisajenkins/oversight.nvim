-- Help overlay floating window

local float = require("oversight.lib.float")

---@class HelpOverlay
---@field buf number Buffer handle
---@field win number Window handle
local HelpOverlay = {}
HelpOverlay.__index = HelpOverlay

-- Default help content for oversight
local DEFAULT_HELP_TEXT = {
	"oversight - Code Review for AI Changes",
	"",
	"Navigation:",
	"  j/k         Scroll up/down",
	"  Ctrl-d/u    Half page down/up",
	"  Ctrl-f/b    Full page down/up (diff view)",
	"  {/}         Previous/next file",
	"  [/]         Previous/next hunk",
	"  g/G         First/last file",
	"  Tab         Switch panels",
	"",
	"File List:",
	"  Enter       Select file (show diff)",
	"  o           Open file in new tab",
	"  r           Toggle file reviewed",
	"",
	"Review:",
	"  c           Add/edit line comment",
	"  C           Add file comment",
	"  dd          Delete comment",
	"",
	"Comment Dialog:",
	"  Ctrl-s/CR   Submit comment",
	"  Esc         Save (or discard if empty)",
	"  q           Discard comment",
	"  Ctrl-t/Tab  Cycle type (Note/Suggestion/Issue/Praise)",
	"",
	"Export & Clear:",
	"  y           Yank comments to clipboard",
	"  X           Clear all comments",
	"",
	"Other:",
	"  R           Refresh status",
	"  ?           Show this help",
	"  q           Quit review",
	"",
	"Press any key to close...",
}

---Show the help overlay
---@param opts? table Options {help_text?: string[], title?: string, width?: number}
---@return HelpOverlay instance
function HelpOverlay.show(opts)
	opts = opts or {}
	local help_text = opts.help_text or DEFAULT_HELP_TEXT
	local title = opts.title or " Help "
	local width = opts.width or 50

	local instance = setmetatable({}, HelpOverlay)

	local state = float.open({
		width = width,
		height = #help_text,
		title = title,
	})
	instance.buf = state.buf
	instance.win = state.win

	-- Set content and lock buffer
	vim.api.nvim_buf_set_lines(instance.buf, 0, -1, false, help_text)
	vim.api.nvim_set_option_value("modifiable", false, { buf = instance.buf })

	-- Setup keymappings to close
	instance:_setup_close_handlers()

	return instance
end

---Setup handlers to close the overlay
function HelpOverlay:_setup_close_handlers()
	-- Close on Escape
	vim.keymap.set("n", "<Esc>", function()
		self:close()
	end, { buffer = self.buf, silent = true })

	-- Close on q
	vim.keymap.set("n", "q", function()
		self:close()
	end, { buffer = self.buf, silent = true })

	-- Close when leaving buffer
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = self.buf,
		once = true,
		callback = function()
			self:close()
		end,
	})
end

---Close the help overlay
function HelpOverlay:close()
	float.close(self)
end

return HelpOverlay
