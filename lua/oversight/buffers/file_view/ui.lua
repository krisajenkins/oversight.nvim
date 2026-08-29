-- Pure UI functions for the file view buffer (browse mode)

local Ui = require("oversight.lib.ui")

local M = {}

---Create file header component
---@param path string File path
---@param reviewed boolean Whether file has been reviewed
---@return Component component File header component
function M.create_file_header(path, reviewed)
	local reviewed_mark = reviewed and "✓" or " "
	local reviewed_hl = reviewed and "OversightReviewed" or "OversightSeparator"

	return Ui.row({
		Ui.text("=== [", { highlight = "OversightSeparator" }),
		Ui.text(reviewed_mark, { highlight = reviewed_hl }),
		Ui.text("] ", { highlight = "OversightSeparator" }),
		Ui.text(path, { highlight = "OversightHeader" }),
		Ui.text(" ===", { highlight = "OversightSeparator" }),
	})
end

---Create a single source line with line number
---@param line_no number Line number
---@param content string Line content
---@param has_comment boolean Whether this line has a comment
---@return Component component File line component
function M.create_file_line(line_no, content, has_comment)
	-- Omit highlight on content so treesitter syntax colors come through.
	-- Only apply an explicit highlight for commented lines.
	local content_hl = has_comment and { highlight = "OversightCommentedLine" } or {}

	return Ui.row({
		Ui.text(string.format("%4d", line_no), { highlight = "OversightLineNumber" }),
		Ui.text(" │ ", { highlight = "OversightSeparator" }),
		Ui.text(content, content_hl),
	}, {
		interactive = true,
		item = {
			type = "file_line",
			line_no = line_no,
		},
	})
end

---Create comment display component (reuses pattern from diff_view/ui.lua)
---@param comment Comment Comment data
---@return Component component Comment component
function M.create_comment(comment)
	local type_hl, type_label = Ui.get_comment_type_display(comment.type)

	return Ui.col({
		Ui.row({
			Ui.text("      ", {}),
			Ui.text(type_label .. " ", { highlight = type_hl }),
			Ui.text(comment.text, { highlight = type_hl }),
		}),
	}, {
		interactive = true,
		item = { comment_id = comment.id, type = "comment" },
	})
end

---Create keybindings hint for browse mode
---@return Component component Hint component
function M.create_keybindings_hint()
	return Ui.row({
		Ui.text("j/k:scroll  {/}:file  o:open  c:comment  C:file comment  r:reviewed  y:yank  ?:help  q:quit", {
			highlight = "Comment",
		}),
	})
end

---Create binary file notice
---@param path string File path
---@return Component component Binary notice component
function M.create_binary_notice(path)
	return Ui.col({
		Ui.empty_line(),
		Ui.text("Binary file: " .. path, { highlight = "Comment" }),
		Ui.text("(cannot display content)", { highlight = "Comment" }),
		Ui.empty_line(),
	})
end

return M
