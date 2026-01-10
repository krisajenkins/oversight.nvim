-- Pure UI functions for the diff view buffer

local Ui = require("tuicr.lib.ui")

local M = {}

---Pad or truncate a string to a specific display width
---Handles multi-byte UTF-8 characters correctly
---@param str string Input string
---@param width number Target display width
---@return string result Padded/truncated string
local function pad_to_width(str, width)
	local display_width = vim.fn.strdisplaywidth(str)
	if display_width >= width then
		-- Truncate with ellipsis if too long
		if display_width > width and width > 3 then
			-- Use strcharpart for proper UTF-8 handling
			-- We need to find how many characters fit in (width - 3) display columns
			local truncated = ""
			local current_width = 0
			local target_width = width - 3

			for char in vim.gsplit(str, "") do
				local char_width = vim.fn.strdisplaywidth(char)
				if current_width + char_width > target_width then
					break
				end
				truncated = truncated .. char
				current_width = current_width + char_width
			end

			return truncated .. "..."
		end
		-- Just return as-is if it fits or barely over
		return str
	end
	-- Pad with spaces to reach target width
	return str .. string.rep(" ", width - display_width)
end

---Create file header component
---@param path string File path
---@param status string Git status
---@param reviewed boolean Whether file has been reviewed
---@return table component File header component
function M.create_file_header(path, status, reviewed)
	local status_hl = Ui.get_status_highlight(status)
	local reviewed_mark = reviewed and "✓" or " "
	local reviewed_hl = reviewed and "TuicrReviewed" or "TuicrSeparator"

	-- Single line format: === [✓] filename (M) ===
	return Ui.row({
		Ui.text("=== [", { highlight = "TuicrSeparator" }),
		Ui.text(reviewed_mark, { highlight = reviewed_hl }),
		Ui.text("] ", { highlight = "TuicrSeparator" }),
		Ui.text(path, { highlight = "TuicrHeader" }),
		Ui.text(" (", { highlight = "TuicrSeparator" }),
		Ui.text(status, { highlight = status_hl }),
		Ui.text(") ", { highlight = "TuicrSeparator" }),
		Ui.text("===", { highlight = "TuicrSeparator" }),
	})
end

---Create side-by-side diff line component
---@param line table DiffLine {line_no_old, line_no_new, content_old, content_new, type}
---@param col_width number Width for each content column
---@param opts? table Additional options (interactive, item)
---@return table component Diff line component
function M.create_diff_line(line, col_width, opts)
	opts = opts or {}

	local old_line_str = line.line_no_old and string.format("%4d", line.line_no_old) or "    "
	local new_line_str = line.line_no_new and string.format("%4d", line.line_no_new) or "    "

	local old_hl = "TuicrDiffContext"
	local new_hl = "TuicrDiffContext"

	if line.type == "add" then
		new_hl = "TuicrDiffAdd"
	elseif line.type == "delete" then
		old_hl = "TuicrDiffDelete"
	elseif line.type == "change" then
		old_hl = "TuicrDiffDelete"
		new_hl = "TuicrDiffAdd"
	elseif line.type == "hunk_header" then
		return Ui.text(line.content_old, { highlight = "TuicrHunkHeader" })
	end

	local old_content = pad_to_width(line.content_old or "", col_width)
	local new_content = pad_to_width(line.content_new or "", col_width)

	return Ui.row({
		Ui.text(old_line_str, { highlight = "TuicrLineNumber" }),
		Ui.text(" ", {}),
		Ui.text(old_content, { highlight = old_hl }),
		Ui.text(" | ", { highlight = "TuicrSeparator" }),
		Ui.text(new_line_str, { highlight = "TuicrLineNumber" }),
		Ui.text(" ", {}),
		Ui.text(new_content, { highlight = new_hl }),
	}, opts)
end

---Create binary file notice
---@param path string File path
---@return table component Binary notice component
function M.create_binary_notice(path)
	return Ui.col({
		Ui.empty_line(),
		Ui.text("Binary file: " .. path, { highlight = "Comment" }),
		Ui.text("(cannot display diff)", { highlight = "Comment" }),
		Ui.empty_line(),
	})
end

---Create no changes notice
---@return table component No changes component
function M.create_no_changes()
	return Ui.col({
		Ui.empty_line(),
		Ui.text("No changes to display", { highlight = "Comment" }),
		Ui.empty_line(),
	})
end

---Create comment display component
---@param comment table Comment {type, text, line, side}
---@return table component Comment component
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

---Create the full diff view for a file
---@param file_diff table FileDiff
---@param comments table[] Comments for this file
---@param col_width number Column width
---@param reviewed boolean Whether file has been reviewed
---@return table[] components UI components
function M.create_file_diff(file_diff, comments, col_width, reviewed)
	local components = {}

	-- File header
	table.insert(components, M.create_file_header(file_diff.path, file_diff.status, reviewed))

	-- If reviewed, fold the diff (only show header)
	if reviewed then
		table.insert(components, Ui.text("  (reviewed - press r to unfold)", { highlight = "Comment" }))
		return components
	end

	-- Binary file handling
	if file_diff.is_binary then
		table.insert(components, M.create_binary_notice(file_diff.path))
		return components
	end

	-- No hunks = no changes
	if #file_diff.hunks == 0 then
		table.insert(components, M.create_no_changes())
		return components
	end

	-- Convert to side-by-side
	local diff_module = require("tuicr.lib.git.diff")
	local side_by_side = diff_module.to_side_by_side(file_diff.hunks)

	-- Build comment lookup by line
	local line_comments = {}
	for _, comment in ipairs(comments) do
		if comment.line then
			local key = string.format("%s:%d", comment.side or "new", comment.line)
			line_comments[key] = line_comments[key] or {}
			table.insert(line_comments[key], comment)
		end
	end

	-- Render diff lines with comments
	for _, line in ipairs(side_by_side) do
		local line_opts = {
			interactive = line.type ~= "hunk_header",
			item = {
				type = "diff_line",
				line_no_old = line.line_no_old,
				line_no_new = line.line_no_new,
				line_type = line.type,
				file = file_diff.path,
			},
		}

		table.insert(components, M.create_diff_line(line, col_width, line_opts))

		-- Add comments after their lines
		if line.line_no_old then
			local key = string.format("old:%d", line.line_no_old)
			for _, comment in ipairs(line_comments[key] or {}) do
				table.insert(components, M.create_comment(comment))
			end
		end
		if line.line_no_new then
			local key = string.format("new:%d", line.line_no_new)
			for _, comment in ipairs(line_comments[key] or {}) do
				table.insert(components, M.create_comment(comment))
			end
		end
	end

	-- Add file-level comments at the end
	for _, comment in ipairs(comments) do
		if not comment.line then
			table.insert(components, M.create_comment(comment))
		end
	end

	return components
end

---Create header showing keybindings hint
---@return table component Header component
function M.create_keybindings_hint()
	return Ui.row({
		Ui.text("j/k:scroll  {/}:file  [/]:hunk  c:comment  r:reviewed  y:yank  ?:help  q:quit", {
			highlight = "Comment",
		}),
	})
end

return M
