-- Tests for UI components

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Component"] = MiniTest.new_set()

T["Component"]["creates text component"] = function()
	local Ui = require("tuicr.lib.ui")

	local component = Ui.text("Hello", { highlight = "Normal" })

	expect.equality(component:get_tag(), "Text")
	expect.equality(component:get_value(), "Hello")
	expect.equality(component:get_highlight(), "Normal")
end

T["Component"]["creates row component"] = function()
	local Ui = require("tuicr.lib.ui")

	local component = Ui.row({
		Ui.text("A"),
		Ui.text("B"),
	})

	expect.equality(component:get_tag(), "Row")
	expect.equality(#component:get_children(), 2)
end

T["Component"]["creates col component"] = function()
	local Ui = require("tuicr.lib.ui")

	local component = Ui.col({
		Ui.text("Line 1"),
		Ui.text("Line 2"),
	})

	expect.equality(component:get_tag(), "Col")
	expect.equality(#component:get_children(), 2)
end

T["Component"]["creates file_item with correct highlights"] = function()
	local Ui = require("tuicr.lib.ui")

	local component = Ui.file_item("A", "src/main.lua", false)

	expect.equality(component:get_tag(), "Row")
	local children = component:get_children()
	expect.equality(#children, 5) -- review icon, space, status, space, path
end

T["Component"]["marks interactive components"] = function()
	local Ui = require("tuicr.lib.ui")

	local component = Ui.text("Click me", { interactive = true })

	expect.equality(component:is_interactive(), true)
end

T["Component"]["supports item data"] = function()
	local Ui = require("tuicr.lib.ui")

	local item_data = { path = "test.lua", status = "M" }
	local component = Ui.text("Test", { item = item_data, interactive = true })

	local retrieved = component:get_item()
	expect.equality(retrieved.path, "test.lua")
	expect.equality(retrieved.status, "M")
end

T["Component"]["sanitizes newlines in text"] = function()
	local Ui = require("tuicr.lib.ui")

	-- \n is replaced with space, \r is removed
	local component = Ui.text("Line1\nLine2\r")

	expect.equality(component:get_value(), "Line1 Line2")
end

return T
