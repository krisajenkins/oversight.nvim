---@class Component
---@field tag string
---@field children table[]
---@field options table
---@field value any
local Component = {}
Component.__index = Component

---Create a new component factory
---@param render_fn function Function that takes props and returns a component definition
---@return function component_factory Component constructor function
function Component.new(render_fn)
	return function(props)
		local component = render_fn(props or {})
		if not component.tag then
			component.tag = "UnknownComponent"
		end
		component.children = component.children or {}
		component.options = component.options or {}

		return setmetatable(component, Component)
	end
end

---Check if this is a component
---@param obj any Object to check
---@return boolean is_component True if object is a component
function Component.is_component(obj)
	return type(obj) == "table" and obj.tag ~= nil
end

---Get the component's tag
---@return string tag The component's tag
function Component:get_tag()
	return self.tag
end

---Get the component's children
---@return table[] children The component's children
function Component:get_children()
	return self.children
end

---Get the component's options
---@return table options The component's options
function Component:get_options()
	return self.options
end

---Get the component's value
---@return any value The component's value
function Component:get_value()
	return self.value
end

---Check if component is foldable
---@return boolean foldable True if component can be folded
function Component:is_foldable()
	return self.options.foldable == true
end

---Check if component is folded
---@return boolean folded True if component is currently folded
function Component:is_folded()
	return self.options.folded == true
end

---Check if component is interactive
---@return boolean interactive True if component supports interactions
function Component:is_interactive()
	return self.options.interactive == true
end

---Get component's section name (for folding state persistence)
---@return string|nil section Section name or nil
function Component:get_section()
	return self.options.section
end

---Get component's item data
---@return any item Item data or nil
function Component:get_item()
	return self.options.item
end

---Get component's highlight group
---@return string|nil highlight Highlight group name or nil
function Component:get_highlight()
	return self.options.highlight
end

---Create a component with a specific tag
---@param tag string The component tag
---@return function component_factory Tagged component constructor
function Component.with_tag(tag)
	return function(children, options)
		return Component.new(function(props)
			return {
				tag = tag,
				children = children or {},
				options = options or {},
				value = props.value,
			}
		end)()
	end
end

return Component
