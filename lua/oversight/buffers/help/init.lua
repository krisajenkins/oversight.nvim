-- Help overlay floating window

local float = require("oversight.lib.float")

---@class HelpOverlay
---@field buf number Buffer handle
---@field win number Window handle
local HelpOverlay = {}
HelpOverlay.__index = HelpOverlay

-- Keybinding help, one text per mode.
--
-- These are documentation, not behaviour: the buffers' own `_setup_mappings`
-- methods (plus the tab-level maps in buffers/review and buffers/browse) are the
-- source of truth, and these lists have to be kept in step with them by hand.
-- See the Keybindings section of CLAUDE.md. `tests/test_help.lua` checks the
-- claims here that are cheap to check mechanically.
--
-- Keys that exist in only one panel say so, because the two panels of a mode do
-- not have the same map set: `g`/`G` are file-list only, and `[`/`]`, `c`, `C`
-- and `dd` are diff-view only.

---Review mode: file list + diff view.
local REVIEW_HELP_TEXT = {
	"oversight - Review Mode",
	"",
	"Navigation:",
	"  j/k         Move/scroll",
	"  Down/Up     Move/scroll",
	"  Ctrl-d/u    Half page down/up",
	"  Ctrl-f/b    Full page down/up (diff view)",
	"  {/}         Previous/next file",
	"  [/]         Previous/next hunk (diff view)",
	"  g/G         First/last file (file list)",
	"  Tab         Switch panels",
	"",
	"File List:",
	"  Enter       Select file (show diff)",
	"  o           Open file in new tab",
	"  r           Toggle file reviewed",
	"",
	"Diff View:",
	"  Enter/o     Open file at current line",
	"  r           Toggle file reviewed",
	"  c           Add/edit line comment",
	"  C           Add file comment",
	"  dd          Delete comment",
	"",
	"Comment Dialog:",
	"  Ctrl-s      Submit comment",
	"  Ctrl-Enter  Submit comment",
	"  Esc         Save (or discard if empty)",
	"  q           Discard comment",
	"  Ctrl-t/Tab  Cycle type",
	"  1/2/3/4     Note/Suggestion/Issue/Praise",
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

---Browse mode: file tree + file view. No diffs, so no hunk navigation.
local BROWSE_HELP_TEXT = {
	"oversight - Browse Mode",
	"",
	"Navigation:",
	"  j/k         Move/scroll",
	"  Down/Up     Move/scroll",
	"  Ctrl-d/u    Half page down/up",
	"  Ctrl-f/b    Full page down/up (file view)",
	"  {/}         Previous/next file",
	"  g/G         First/last item (file tree)",
	"  Tab         Switch panels",
	"",
	"File Tree:",
	"  Enter       Expand/collapse dir, or select file",
	"  l/h         Expand/collapse directory",
	"  Right/Left  Expand/collapse directory",
	"  o           Open file in new tab",
	"  r           Toggle reviewed (file or directory)",
	"",
	"File View:",
	"  Enter/o     Open file at current line",
	"  r           Toggle file reviewed",
	"  c           Add/edit line comment",
	"  C           Add file comment",
	"  dd          Delete comment",
	"",
	"Comment Dialog:",
	"  Ctrl-s      Submit comment",
	"  Ctrl-Enter  Submit comment",
	"  Esc         Save (or discard if empty)",
	"  q           Discard comment",
	"  Ctrl-t/Tab  Cycle type",
	"  1/2/3/4     Note/Suggestion/Issue/Praise",
	"",
	"Export & Clear:",
	"  y           Yank notes to clipboard",
	"  X           Clear all notes",
	"",
	"Other:",
	"  R           Refresh file list",
	"  ?           Show this help",
	"  q           Quit browse",
	"",
	"Press any key to close...",
}

HelpOverlay.REVIEW_HELP_TEXT = REVIEW_HELP_TEXT
HelpOverlay.BROWSE_HELP_TEXT = BROWSE_HELP_TEXT

local DEFAULT_HELP_TEXT = REVIEW_HELP_TEXT

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
