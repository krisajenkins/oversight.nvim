-- Tests for Buffer abstraction

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Buffer"] = MiniTest.new_set()

T["Buffer"]["creates buffer with name"] = function()
	local Buffer = require("oversight.lib.buffer")

	local buf = Buffer.new({
		name = "oversight://test-buffer",
		filetype = "oversight-test",
	})

	expect.equality(buf:get_name(), "oversight://test-buffer")
	expect.equality(buf:is_valid(), true)

	buf:close()
end

T["Buffer"]["creates buffer with filetype"] = function()
	local Buffer = require("oversight.lib.buffer")

	local buf = Buffer.new({
		name = "oversight://test-filetype",
		filetype = "oversight-custom",
	})

	local ft = vim.api.nvim_get_option_value("filetype", { buf = buf:get_handle() })
	expect.equality(ft, "oversight-custom")

	buf:close()
end

T["Buffer"]["get_handle returns valid handle"] = function()
	local Buffer = require("oversight.lib.buffer")

	local buf = Buffer.new({
		name = "oversight://test-handle",
		filetype = "oversight-test",
	})

	local handle = buf:get_handle()
	expect.equality(vim.api.nvim_buf_is_valid(handle), true)

	buf:close()
end

T["Buffer"]["close invalidates buffer"] = function()
	local Buffer = require("oversight.lib.buffer")

	local buf = Buffer.new({
		name = "oversight://test-close",
		filetype = "oversight-test",
	})

	local handle = buf:get_handle()
	expect.equality(vim.api.nvim_buf_is_valid(handle), true)

	buf:close()

	expect.equality(vim.api.nvim_buf_is_valid(handle), false)
end

T["Buffer"]["renders components to buffer"] = function()
	local Buffer = require("oversight.lib.buffer")
	local Ui = require("oversight.lib.ui")

	local buf = Buffer.new({
		name = "oversight://test-render",
		filetype = "oversight-test",
	})

	buf:render({
		Ui.text("Hello World"),
		Ui.text("Second Line"),
	})

	local lines = buf:get_lines(0, -1)
	expect.equality(lines[1], "Hello World")
	expect.equality(lines[2], "Second Line")

	buf:close()
end

T["Buffer"]["line_count returns correct count"] = function()
	local Buffer = require("oversight.lib.buffer")
	local Ui = require("oversight.lib.ui")

	local buf = Buffer.new({
		name = "oversight://test-linecount",
		filetype = "oversight-test",
	})

	buf:render({
		Ui.text("Line 1"),
		Ui.text("Line 2"),
		Ui.text("Line 3"),
	})

	expect.equality(buf:line_count(), 3)

	buf:close()
end

T["Buffer"]["get_lines returns buffer content"] = function()
	local Buffer = require("oversight.lib.buffer")
	local Ui = require("oversight.lib.ui")

	local buf = Buffer.new({
		name = "oversight://test-getlines",
		filetype = "oversight-test",
	})

	buf:render({
		Ui.text("Alpha"),
		Ui.text("Beta"),
		Ui.text("Gamma"),
	})

	-- Get all lines
	local all_lines = buf:get_lines(0, -1)
	expect.equality(#all_lines, 3)
	expect.equality(all_lines[1], "Alpha")
	expect.equality(all_lines[3], "Gamma")

	-- Get subset of lines
	local subset = buf:get_lines(1, 2)
	expect.equality(#subset, 1)
	expect.equality(subset[1], "Beta")

	buf:close()
end

T["Buffer"]["respects modifiable config"] = function()
	local Buffer = require("oversight.lib.buffer")

	local buf = Buffer.new({
		name = "oversight://test-modifiable",
		filetype = "oversight-test",
		modifiable = false,
	})

	-- After render, modifiable should be restored to false
	local Ui = require("oversight.lib.ui")
	buf:render({ Ui.text("Test") })

	local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = buf:get_handle() })
	expect.equality(modifiable, false)

	buf:close()
end

T["Buffer"]["respects readonly config"] = function()
	local Buffer = require("oversight.lib.buffer")

	local buf = Buffer.new({
		name = "oversight://test-readonly",
		filetype = "oversight-test",
		readonly = true,
	})

	local readonly = vim.api.nvim_get_option_value("readonly", { buf = buf:get_handle() })
	expect.equality(readonly, true)

	buf:close()
end

T["Buffer"]["refresh re-renders components"] = function()
	local Buffer = require("oversight.lib.buffer")
	local Ui = require("oversight.lib.ui")

	local buf = Buffer.new({
		name = "oversight://test-refresh",
		filetype = "oversight-test",
	})

	buf:render({
		Ui.text("Initial"),
	})

	expect.equality(buf:get_lines(0, -1)[1], "Initial")

	-- Modify components and refresh
	buf:render({
		Ui.text("Updated"),
	})

	expect.equality(buf:get_lines(0, -1)[1], "Updated")

	buf:close()
end

T["Buffer"]["reuses existing buffer with same name"] = function()
	local Buffer = require("oversight.lib.buffer")

	local buf1 = Buffer.new({
		name = "oversight://test-reuse",
		filetype = "oversight-test",
	})

	local handle1 = buf1:get_handle()

	-- Create another buffer with same name
	local buf2 = Buffer.new({
		name = "oversight://test-reuse",
		filetype = "oversight-test",
	})

	local handle2 = buf2:get_handle()

	-- Should reuse the same buffer
	expect.equality(handle1, handle2)

	buf1:close()
end

return T
