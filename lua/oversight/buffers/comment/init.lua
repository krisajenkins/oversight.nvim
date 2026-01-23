-- Comment input floating window

local float = require("oversight.lib.float")

---@class CommentInputOpts
---@field context CommentContext Comment context (file, line, side)
---@field existing_comment? Comment Optional existing comment for editing
---@field on_submit? fun(comment: CommentData): nil Callback when comment is submitted
---@field on_cancel? fun(): nil Callback when input is cancelled

---@class CommentInput
---@field buf number Buffer handle
---@field win number Window handle
---@field context CommentContext Comment context (file, line, side)
---@field comment_type "note"|"suggestion"|"issue"|"praise" Current comment type
---@field existing_comment? Comment Optional existing comment being edited
---@field on_submit? fun(comment: CommentData): nil Callback when comment is submitted
---@field on_cancel? fun(): nil Callback when input is cancelled
local CommentInput = {}
CommentInput.__index = CommentInput

local COMMENT_TYPES = { "note", "suggestion", "issue", "praise" }

---Create a new comment input window
---@param opts CommentInputOpts Options
---@return CommentInput instance
function CommentInput.new(opts)
	local existing = opts.existing_comment
	local instance = setmetatable({
		context = opts.context,
		comment_type = existing and existing.type or "note",
		existing_comment = existing,
		on_submit = opts.on_submit,
		on_cancel = opts.on_cancel,
	}, CommentInput)

	instance:_create_window()

	return instance
end

---Create the floating window
function CommentInput:_create_window()
	local title = self.existing_comment and " Edit Comment " or " Add Comment "
	local state = float.open({
		width = math.min(80, vim.o.columns - 10),
		height = 10,
		title = title,
		filetype = "oversight-comment",
	})
	self.buf = state.buf
	self.win = state.win

	-- Set window options
	vim.api.nvim_set_option_value("wrap", true, { win = self.win })
	vim.api.nvim_set_option_value("cursorline", false, { win = self.win })

	-- Set initial content
	self:_update_content()

	-- Setup keymappings
	self:_setup_mappings()

	-- Enter insert mode at the end
	vim.cmd("startinsert")
	vim.api.nvim_win_set_cursor(self.win, { 4, 0 })
end

---Update window content
function CommentInput:_update_content()
	local type_line = "Type: "
	for i, t in ipairs(COMMENT_TYPES) do
		if t == self.comment_type then
			type_line = type_line .. "[" .. t:upper() .. "]"
		else
			type_line = type_line .. " " .. t
		end
		if i < #COMMENT_TYPES then
			type_line = type_line .. " "
		end
	end
	type_line = type_line .. "  (Ctrl-t to change)"

	local context_line = "File: " .. (self.context.file or "")
	if self.context.line then
		context_line = context_line .. " Line: " .. self.context.line
		if self.context.side then
			context_line = context_line .. " (" .. self.context.side .. ")"
		end
	else
		context_line = context_line .. " (file-level comment)"
	end

	-- Get existing text (preserve user input) - only if buffer has content
	local existing_lines = {}
	local line_count = vim.api.nvim_buf_line_count(self.buf)
	if line_count > 3 then
		existing_lines = vim.api.nvim_buf_get_lines(self.buf, 3, -1, false)
	end

	local lines = {
		type_line,
		context_line,
		string.rep("-", 60),
	}

	-- Add existing comment text or empty line
	if #existing_lines > 0 and existing_lines[1] ~= "" then
		vim.list_extend(lines, existing_lines)
	elseif self.existing_comment then
		-- Pre-fill with existing comment text when editing
		for line in vim.gsplit(self.existing_comment.text, "\n", { plain = true }) do
			table.insert(lines, line)
		end
	else
		table.insert(lines, "")
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf })
	-- Write all lines including the input area
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf })
end

---Setup keymappings
function CommentInput:_setup_mappings()
	local opts = { buffer = self.buf, silent = true }

	-- Submit with Ctrl+S or Ctrl+Enter (works in both modes)
	vim.keymap.set({ "n", "i" }, "<C-s>", function()
		self:_submit()
	end, opts)

	vim.keymap.set({ "n", "i" }, "<C-CR>", function()
		self:_submit()
	end, opts)

	-- Escape saves if there's content, otherwise discards
	vim.keymap.set("i", "<Esc>", function()
		vim.cmd("stopinsert")
		self:_save_or_discard()
	end, opts)

	vim.keymap.set("n", "<Esc>", function()
		self:_save_or_discard()
	end, opts)

	-- q always cancels (explicit discard)
	vim.keymap.set("n", "q", function()
		self:_cancel()
	end, opts)

	-- Cycle comment type with Ctrl+t (Tab is for indenting in insert mode)
	vim.keymap.set({ "n", "i" }, "<C-t>", function()
		self:_cycle_type()
	end, opts)

	-- Also allow Tab in normal mode
	vim.keymap.set("n", "<Tab>", function()
		self:_cycle_type()
	end, opts)

	-- Direct type selection
	vim.keymap.set("n", "1", function()
		self:_set_type("note")
	end, opts)
	vim.keymap.set("n", "2", function()
		self:_set_type("suggestion")
	end, opts)
	vim.keymap.set("n", "3", function()
		self:_set_type("issue")
	end, opts)
	vim.keymap.set("n", "4", function()
		self:_set_type("praise")
	end, opts)
end

---Cycle to next comment type
function CommentInput:_cycle_type()
	local current_idx = 1
	for i, t in ipairs(COMMENT_TYPES) do
		if t == self.comment_type then
			current_idx = i
			break
		end
	end

	local next_idx = (current_idx % #COMMENT_TYPES) + 1
	self.comment_type = COMMENT_TYPES[next_idx]
	self:_update_content()
end

---Set comment type directly
---@param comment_type string New comment type
function CommentInput:_set_type(comment_type)
	self.comment_type = comment_type
	self:_update_content()
end

---Save comment if there's content, otherwise discard
function CommentInput:_save_or_discard()
	-- Get comment text (lines after the separator)
	local lines = vim.api.nvim_buf_get_lines(self.buf, 3, -1, false)
	local text = vim.trim(table.concat(lines, "\n"))

	if text == "" then
		-- Empty comment, just discard silently
		self:_cancel()
	else
		-- Has content, save it
		self:_submit()
	end
end

---Submit the comment
function CommentInput:_submit()
	-- Exit insert mode first to prevent staying in insert mode after window closes
	vim.cmd("stopinsert")

	-- Get comment text (lines after the separator)
	local lines = vim.api.nvim_buf_get_lines(self.buf, 3, -1, false)
	local text = vim.trim(table.concat(lines, "\n"))

	if text == "" then
		vim.notify("Comment text is empty", vim.log.levels.WARN)
		return
	end

	-- Close window
	self:close()

	-- Call callback
	if self.on_submit then
		self.on_submit({
			id = self.existing_comment and self.existing_comment.id or nil,
			file = self.context.file,
			line = self.context.line,
			side = self.context.side,
			type = self.comment_type,
			text = text,
		})
	end
end

---Cancel the comment
function CommentInput:_cancel()
	self:close()

	if self.on_cancel then
		self.on_cancel()
	end
end

---Close the window
function CommentInput:close()
	float.close(self)
end

return CommentInput
