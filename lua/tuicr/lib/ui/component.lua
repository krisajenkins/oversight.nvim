---@class ComponentOptions
---@field highlight? string Highlight group name
---@field foldable? boolean Whether component can be folded
---@field folded? boolean Whether component is currently folded
---@field interactive? boolean Whether component supports interactions
---@field section? string Section name for folding state persistence
---@field item? any Item data (e.g., LineInfo for diff lines)

---@class Component
---@field tag string Component type identifier
---@field children Component[] Child components
---@field options ComponentOptions Component options
---@field value any Component value (e.g., text content)
local Component = {}
Component.__index = Component

---Create a new component factory
---@param render_fn fun(props: table): {tag: string, children?: Component[], options?: ComponentOptions, value?: any} Render function
---@return fun(props?: table): Component component_factory Component constructor function
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
---@return Component[] children The component's children
function Component:get_children()
	return self.children
end

---Get the component's options
---@return ComponentOptions options The component's options
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
---@return fun(children?: Component[], options?: ComponentOptions): Component component_factory Tagged component constructor
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
