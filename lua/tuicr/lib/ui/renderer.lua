local Component = require("tuicr.lib.ui.component")

---@class Renderer
local Renderer = {}

---@class RenderContext
---@field buffer number Buffer handle
---@field lines string[] Accumulated lines
---@field highlights table[] Highlight specifications
---@field extmarks table[] Extmark specifications
---@field line_number number Current line number (0-indexed)
---@field col_offset number Current column offset
---@field component_positions table[] Component position mappings {line -> component}

---Create a new render context
---@param buffer number Buffer handle
---@return RenderContext context Render context
function Renderer.new_context(buffer)
	return {
		buffer = buffer,
		lines = {},
		highlights = {},
		extmarks = {},
		line_number = 0,
		col_offset = 0,
		component_positions = {},
	}
end

---Add a line to the render context
---@param context RenderContext Render context
---@param text string Line text
---@param highlight? string Highlight group
function Renderer.add_line(context, text, highlight)
	table.insert(context.lines, text)

	if highlight then
		table.insert(context.highlights, {
			group = highlight,
			line = context.line_number,
			col_start = 0,
			col_end = #text,
		})
	end

	context.line_number = context.line_number + 1
end

---Add text to the current line in the render context
---@param context RenderContext Render context
---@param text string Text to add
---@param highlight? string Highlight group
function Renderer.add_text(context, text, highlight)
	if #context.lines == 0 then
		table.insert(context.lines, "")
	end

	local line_idx = #context.lines
	local current_line = context.lines[line_idx]
	local start_col = #current_line

	context.lines[line_idx] = current_line .. text

	if highlight then
		table.insert(context.highlights, {
			group = highlight,
			line = context.line_number,
			col_start = start_col,
			col_end = start_col + #text,
		})
	end
end

---Render a component tree to lines and highlights
---@param component table Component to render
---@param context RenderContext Render context
function Renderer.render_component(component, context)
	if not Component.is_component(component) then
		return
	end

	local tag = component:get_tag()
	local children = component:get_children()
	local value = component:get_value()

	-- Track interactive components at their starting line
	if component:is_interactive() then
		context.component_positions[context.line_number] = component
	end

	-- Handle folded components
	if component:is_foldable() and component:is_folded() then
		-- Only render the header for folded components
		if tag == "Col" then
			local header_child = children[1]
			if header_child then
				Renderer.render_component(header_child, context)
			end
			return
		end
	end

	-- Render based on component type
	if tag == "Text" then
		Renderer.add_text(context, value or "", component:get_highlight())
	elseif tag == "Col" then
		-- Render children vertically
		for i, child in ipairs(children) do
			if i > 1 then
				-- Start a new line for each child except the first
				Renderer.add_line(context, "", nil)
			end
			Renderer.render_component(child, context)
		end
	elseif tag == "Row" then
		-- Render children horizontally
		for _, child in ipairs(children) do
			Renderer.render_component(child, context)
		end
	else
		-- Default: render as column
		for i, child in ipairs(children) do
			if i > 1 then
				Renderer.add_line(context, "", nil)
			end
			Renderer.render_component(child, context)
		end
	end
end

---Render components to buffer
---@param buffer number Buffer handle
---@param components table[] Components to render
---@return table component_positions Component position mappings {line -> component}
function Renderer.render_to_buffer(buffer, components)
	local context = Renderer.new_context(buffer)

	-- Render all components
	for i, component in ipairs(components) do
		if i > 1 then
			Renderer.add_line(context, "", nil)
		end
		Renderer.render_component(component, context)
	end

	-- Ensure we have at least one line
	if #context.lines == 0 then
		table.insert(context.lines, "")
	end

	-- Strip trailing empty lines to keep buffer tidy
	while #context.lines > 1 and context.lines[#context.lines] == "" do
		table.remove(context.lines)
	end

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, context.lines)

	-- Apply highlights
	local namespace = vim.api.nvim_create_namespace("tuicr_ui")
	vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

	for _, hl in ipairs(context.highlights) do
		vim.api.nvim_buf_add_highlight(buffer, namespace, hl.group, hl.line, hl.col_start, hl.col_end)
	end

	-- Apply extmarks
	for _, extmark in ipairs(context.extmarks) do
		vim.api.nvim_buf_set_extmark(buffer, namespace, extmark.line, extmark.col, extmark.opts)
	end

	-- Return component positions for cursor interaction
	return context.component_positions
end

return Renderer
