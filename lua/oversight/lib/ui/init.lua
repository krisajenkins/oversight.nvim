local Component = require("oversight.lib.ui.component")

---@class Ui
local Ui = {}

---Get highlight group for git status
---@param status string Git status (A, M, D, R, C, etc.)
---@return string highlight Highlight group name
function Ui.get_status_highlight(status)
	if status == "A" then
		return "OversightFileAdded"
	elseif status == "D" then
		return "OversightFileDeleted"
	elseif status == "R" then
		return "OversightFileRenamed"
	elseif status == "C" then
		return "OversightFileCopied"
	end
	return "OversightFileModified"
end

---Get highlight group and label for comment type
---@param comment_type string Comment type (note, suggestion, issue, praise)
---@return string highlight, string label Highlight group and label text
function Ui.get_comment_type_display(comment_type)
	if comment_type == "suggestion" then
		return "OversightCommentSuggestion", "[SUGGESTION]"
	elseif comment_type == "issue" then
		return "OversightCommentIssue", "[ISSUE]"
	elseif comment_type == "praise" then
		return "OversightCommentPraise", "[PRAISE]"
	end
	return "OversightCommentNote", "[NOTE]"
end

---Create a column (vertical container)
---@param children Component[] List of child components
---@param options? ComponentOptions Component options
---@return Component component Column component
function Ui.col(children, options)
	return Component.new(function(props)
		return {
			tag = "Col",
			children = children or {},
			options = options or {},
			value = props.value,
		}
	end)()
end

---Create a row (horizontal container)
---@param children Component[] List of child components
---@param options? ComponentOptions Component options
---@return Component component Row component
function Ui.row(children, options)
	return Component.new(function(props)
		return {
			tag = "Row",
			children = children or {},
			options = options or {},
			value = props.value,
		}
	end)()
end

---Create a text component
---@param value string Text content
---@param options? ComponentOptions Component options
---@return Component component Text component
function Ui.text(value, options)
	return Component.new(function(props)
		-- Sanitize value to remove any newlines that could cause rendering issues
		local sanitized_value = (value or ""):gsub("\n", " "):gsub("\r", "")
		return {
			tag = "Text",
			children = {},
			options = options or {},
			value = sanitized_value,
		}
	end)()
end

---Create an empty line component
---@return Component component Empty line component
function Ui.empty_line()
	return Ui.text("", {})
end

---Create a section header component
---@param title string Section title
---@param count? number Optional item count
---@param options? ComponentOptions Component options
---@return Component component Section header component
function Ui.section_header(title, count, options)
	local display_title = title
	if count and count > 0 then
		display_title = title .. " (" .. count .. ")"
	end

	return Ui.text(
		display_title,
		vim.tbl_extend("force", options or {}, {
			highlight = "OversightHeader",
		})
	)
end

---Create a file item component for the file list
---@param status string Git status (A, M, D, etc.)
---@param path string File path
---@param reviewed boolean Whether file is reviewed
---@param options? ComponentOptions Component options
---@return Component component File item component
function Ui.file_item(status, path, reviewed, options)
	local status_hl = Ui.get_status_highlight(status)
	local review_icon = reviewed and "[x]" or "[ ]"
	local review_hl = reviewed and "OversightReviewed" or "OversightPending"

	return Ui.row({
		Ui.text(review_icon, { highlight = review_hl }),
		Ui.text(" "),
		Ui.text(status, { highlight = status_hl }),
		Ui.text(" "),
		Ui.text(path, { highlight = "Normal" }),
	}, options)
end

---Create a diff line component
---@param line_no_old number|nil Old line number
---@param line_no_new number|nil New line number
---@param content_old string Old content
---@param content_new string New content
---@param line_type string "add"|"delete"|"context"|"empty"
---@param options? ComponentOptions Component options
---@return Component component Diff line component
function Ui.diff_line(line_no_old, line_no_new, content_old, content_new, line_type, options)
	local old_hl = "OversightDiffContext"
	local new_hl = "OversightDiffContext"

	if line_type == "add" then
		new_hl = "OversightDiffAdd"
	elseif line_type == "delete" then
		old_hl = "OversightDiffDelete"
	end

	local old_line_str = line_no_old and string.format("%4d", line_no_old) or "    "
	local new_line_str = line_no_new and string.format("%4d", line_no_new) or "    "

	return Ui.row({
		Ui.text(old_line_str, { highlight = "OversightLineNumber" }),
		Ui.text(" ", {}),
		Ui.text(content_old, { highlight = old_hl }),
		Ui.text(" | ", { highlight = "OversightSeparator" }),
		Ui.text(new_line_str, { highlight = "OversightLineNumber" }),
		Ui.text(" ", {}),
		Ui.text(content_new, { highlight = new_hl }),
	}, options)
end

---Create a hunk header component
---@param header string Hunk header text (e.g., "@@ -1,3 +1,4 @@")
---@param options? ComponentOptions Component options
---@return Component component Hunk header component
function Ui.hunk_header(header, options)
	return Ui.text(
		header,
		vim.tbl_extend("force", options or {}, {
			highlight = "OversightHunkHeader",
		})
	)
end

---Create a file header component for diff view
---@param path string File path
---@param status string Git status
---@param options? ComponentOptions Component options
---@return Component component File header component
function Ui.file_header(path, status, options)
	local status_hl = Ui.get_status_highlight(status)
	local separator = string.rep("=", 3)
	return Ui.row({
		Ui.text(separator .. " ", { highlight = "OversightSeparator" }),
		Ui.text(path, { highlight = "OversightHeader" }),
		Ui.text(" [", { highlight = "OversightSeparator" }),
		Ui.text(status, { highlight = status_hl }),
		Ui.text("] ", { highlight = "OversightSeparator" }),
		Ui.text(separator, { highlight = "OversightSeparator" }),
	}, options)
end

---Create a comment display component
---@param comment_type "note"|"suggestion"|"issue"|"praise" Comment type
---@param text string Comment text
---@param options? ComponentOptions Component options
---@return Component component Comment component
function Ui.comment(comment_type, text, options)
	local type_hl, type_label = Ui.get_comment_type_display(comment_type)

	return Ui.col({
		Ui.row({
			Ui.text("    ", {}),
			Ui.text(type_label, { highlight = type_hl }),
		}),
		Ui.row({
			Ui.text("    ", {}),
			Ui.text(text, { highlight = type_hl }),
		}),
	}, options)
end

---Create a section component
---@param title string Section title
---@param items Component[] Section items
---@param options? ComponentOptions Component options
---@return Component component Section component
function Ui.section(title, items, options)
	local section_options = vim.tbl_extend("force", options or {}, {
		foldable = true,
		section = title:lower():gsub("%s+", "_"),
	})

	local children = {
		Ui.section_header(title, #items),
	}

	for _, item in ipairs(items) do
		table.insert(children, item)
	end

	return Ui.col(children, section_options)
end

return Ui
