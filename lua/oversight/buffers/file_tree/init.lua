-- File tree buffer controller (browse mode left panel)
-- Directory tree navigator for browsing all tracked files

local Buffer = require("oversight.lib.buffer")
local EventEmitter = require("oversight.lib.events")
local FileTreeUI = require("oversight.buffers.file_tree.ui")

-- Events emitted by FileTreeBuffer:
---@alias FileTreeBufferEvent
---| "file_select" # (file: File) - File was selected
---| "toggle_reviewed" # (file: File) - File reviewed status was toggled
---| "open_file" # (file: File) - Request to open file in editor

---@class TreeNode
---@field name string Node name (directory or file name)
---@field path string Full relative path
---@field is_dir boolean Whether this is a directory
---@field children TreeNode[] Child nodes (dirs first, then files, alphabetical)
---@field expanded boolean Whether directory is expanded

---@class FileTreeBufferOpts
---@field files File[] List of files
---@field session ReviewSession Review session
---@field branch? string Current branch name

---@class FileTreeBuffer
---@field buffer Buffer Buffer instance
---@field events EventEmitter Event emitter
---@field files File[] Flat file list
---@field visible_nodes table[] Flattened visible nodes for cursor tracking
---@field current_index number Current selection index in visible_nodes (1-indexed)
---@field separator_at number|nil Index in visible_nodes where separator appears before
---@field session ReviewSession Review session
---@field branch? string Current branch name
---@field expanded table<string, boolean> Expanded state per directory path
local FileTreeBuffer = {}
FileTreeBuffer.__index = FileTreeBuffer

---Create a new file tree buffer
---@param opts FileTreeBufferOpts Options
---@return FileTreeBuffer instance
function FileTreeBuffer.new(opts)
	local files = opts.files or {}
	local instance = setmetatable({
		files = files,
		session = opts.session,
		branch = opts.branch,
		events = EventEmitter.new(),
		visible_nodes = {},
		current_index = 1,
		separator_at = nil,
		expanded = {},
	}, FileTreeBuffer)

	instance.buffer = Buffer.new({
		name = "oversight://file-tree",
		filetype = "oversight-file-tree",
		modifiable = false,
		readonly = true,
	})

	instance:_update_visible_nodes()
	instance:_setup_mappings()

	return instance
end

---Build tree structure from flat file list
---@param files File[] Flat file list
---@return TreeNode root Root tree node
function FileTreeBuffer:_build_tree(files)
	local root = { name = "", path = "", is_dir = true, children = {}, expanded = true }

	for _, file in ipairs(files) do
		local parts = vim.split(file.path, "/")
		local current = root

		for i, part in ipairs(parts) do
			if i == #parts then
				-- File leaf
				table.insert(current.children, {
					name = part,
					path = file.path,
					is_dir = false,
					children = {},
					expanded = false,
				})
			else
				-- Directory node - find or create
				local found = nil
				for _, child in ipairs(current.children) do
					if child.is_dir and child.name == part then
						found = child
						break
					end
				end
				if not found then
					local dir_path = table.concat(parts, "/", 1, i)
					found = {
						name = part,
						path = dir_path,
						is_dir = true,
						children = {},
						expanded = false,
					}
					table.insert(current.children, found)
				end
				current = found
			end
		end
	end

	-- Sort children: directories first (alphabetical), then files (alphabetical)
	self:_sort_tree(root)

	return root
end

---Recursively sort tree nodes
---@param node TreeNode Node to sort
function FileTreeBuffer:_sort_tree(node)
	table.sort(node.children, function(a, b)
		if a.is_dir ~= b.is_dir then
			return a.is_dir
		end
		return a.name < b.name
	end)
	for _, child in ipairs(node.children) do
		if child.is_dir then
			self:_sort_tree(child)
		end
	end
end

---Build flattened list of visible nodes from two trees (unreviewed + reviewed)
function FileTreeBuffer:_update_visible_nodes()
	self.visible_nodes = {}
	self.separator_at = nil

	-- Split files into unreviewed and reviewed
	local unreviewed = {}
	local reviewed = {}
	for _, file in ipairs(self.files) do
		if file.reviewed then
			table.insert(reviewed, file)
		else
			table.insert(unreviewed, file)
		end
	end

	-- Build and flatten unreviewed tree
	if #unreviewed > 0 then
		local tree = self:_build_tree(unreviewed)
		self:_restore_expanded(tree)
		self:_flatten_visible(tree, 0)
	end

	-- Mark separator position
	if #unreviewed > 0 and #reviewed > 0 then
		self.separator_at = #self.visible_nodes + 1
	end

	-- Build and flatten reviewed tree
	if #reviewed > 0 then
		local tree = self:_build_tree(reviewed)
		self:_restore_expanded(tree)
		self:_flatten_visible(tree, 0)
	end
end

---Recursively flatten visible nodes (appends to self.visible_nodes)
---@param node TreeNode Current node
---@param depth number Current indentation depth
function FileTreeBuffer:_flatten_visible(node, depth)
	-- Skip the root node itself
	if node.path ~= "" then
		table.insert(self.visible_nodes, {
			node = node,
			depth = depth,
		})
	end

	if node.is_dir and node.expanded then
		local child_depth = node.path == "" and 0 or depth + 1
		for _, child in ipairs(node.children) do
			self:_flatten_visible(child, child_depth)
		end
	end
end

---Restore expanded state from saved state (defaults to expanded)
---@param node TreeNode Node to restore
function FileTreeBuffer:_restore_expanded(node)
	if node.is_dir then
		if self.expanded[node.path] ~= nil then
			node.expanded = self.expanded[node.path]
		else
			node.expanded = true
			self.expanded[node.path] = true
		end
		for _, child in ipairs(node.children) do
			self:_restore_expanded(child)
		end
	end
end

---Get file data for a tree node path
---@param path string File path
---@return File|nil file File data or nil
function FileTreeBuffer:_get_file(path)
	for _, file in ipairs(self.files) do
		if file.path == path then
			return file
		end
	end
	return nil
end

---Get all files under a directory path
---@param dir_path string Directory path
---@return File[] files Files under the directory
function FileTreeBuffer:_get_files_under_dir(dir_path)
	local result = {}
	local prefix = dir_path .. "/"
	for _, file in ipairs(self.files) do
		if file.path:sub(1, #prefix) == prefix then
			table.insert(result, file)
		end
	end
	return result
end

---Setup keymappings
function FileTreeBuffer:_setup_mappings()
	local buf = self.buffer

	buf:map("n", "j", function()
		self:move_cursor(1)
	end, { desc = "Move down" })

	buf:map("n", "k", function()
		self:move_cursor(-1)
	end, { desc = "Move up" })

	buf:map("n", "g", function()
		self:move_to(1)
	end, { desc = "Go to first" })

	buf:map("n", "G", function()
		self:move_to(#self.visible_nodes)
	end, { desc = "Go to last" })

	buf:map("n", "<CR>", function()
		self:activate_current()
	end, { desc = "Expand/collapse dir or select file" })

	buf:map("n", "l", function()
		self:expand_current()
	end, { desc = "Expand directory" })

	buf:map("n", "h", function()
		self:collapse_current()
	end, { desc = "Collapse directory" })

	buf:map("n", "o", function()
		self:open_file()
	end, { desc = "Open file in editor" })

	buf:map("n", "r", function()
		self:toggle_reviewed()
	end, { desc = "Toggle reviewed" })

	buf:map("n", "<C-d>", function()
		local half = math.floor(vim.api.nvim_win_get_height(0) / 2)
		self:move_cursor(half)
	end, { desc = "Half page down" })

	buf:map("n", "<C-u>", function()
		local half = math.floor(vim.api.nvim_win_get_height(0) / 2)
		self:move_cursor(-half)
	end, { desc = "Half page up" })
end

---Move cursor by delta
---@param delta number Number of nodes to move (positive = down)
function FileTreeBuffer:move_cursor(delta)
	if #self.visible_nodes == 0 then
		return
	end

	local new_index = self.current_index + delta
	new_index = math.max(1, math.min(new_index, #self.visible_nodes))

	if new_index ~= self.current_index then
		self.current_index = new_index
		self:render()

		-- Emit file_select if we landed on a file
		local entry = self.visible_nodes[self.current_index]
		if entry and not entry.node.is_dir then
			local file = self:_get_file(entry.node.path)
			if file then
				self.events:emit("file_select", file)
			end
		end
	end
end

---Move to specific index
---@param index number Target index
function FileTreeBuffer:move_to(index)
	if #self.visible_nodes == 0 then
		return
	end

	index = math.max(1, math.min(index, #self.visible_nodes))
	if index ~= self.current_index then
		self.current_index = index
		self:render()

		local entry = self.visible_nodes[self.current_index]
		if entry and not entry.node.is_dir then
			local file = self:_get_file(entry.node.path)
			if file then
				self.events:emit("file_select", file)
			end
		end
	end
end

---Activate current node (toggle dir expand or select file)
function FileTreeBuffer:activate_current()
	if #self.visible_nodes == 0 then
		return
	end

	local entry = self.visible_nodes[self.current_index]
	if not entry then
		return
	end

	if entry.node.is_dir then
		-- Toggle expanded state via the shared expanded table
		local new_state = self.expanded[entry.node.path] == false
		self.expanded[entry.node.path] = new_state
		self:_update_visible_nodes()
		self.current_index = math.min(self.current_index, #self.visible_nodes)
		self:render()
	else
		local file = self:_get_file(entry.node.path)
		if file then
			self.events:emit("file_select", file)
		end
	end
end

---Expand current directory
function FileTreeBuffer:expand_current()
	if #self.visible_nodes == 0 then
		return
	end

	local entry = self.visible_nodes[self.current_index]
	if entry and entry.node.is_dir and not self.expanded[entry.node.path] then
		self.expanded[entry.node.path] = true
		self:_update_visible_nodes()
		self:render()
	end
end

---Collapse current directory (or parent if on a file/collapsed dir)
function FileTreeBuffer:collapse_current()
	if #self.visible_nodes == 0 then
		return
	end

	local entry = self.visible_nodes[self.current_index]
	if not entry then
		return
	end

	if entry.node.is_dir and self.expanded[entry.node.path] then
		self.expanded[entry.node.path] = false
		self:_update_visible_nodes()
		self.current_index = math.min(self.current_index, #self.visible_nodes)
		self:render()
	end
end

---Open file in editor
function FileTreeBuffer:open_file()
	if #self.visible_nodes == 0 then
		return
	end

	local entry = self.visible_nodes[self.current_index]
	if entry and not entry.node.is_dir then
		local file = self:_get_file(entry.node.path)
		if file then
			self.events:emit("open_file", file)
		end
	end
end

---Emit file_select for whatever file is now under the cursor
function FileTreeBuffer:_emit_current_file_select()
	if #self.visible_nodes == 0 then
		return
	end
	local entry = self.visible_nodes[self.current_index]
	if entry and not entry.node.is_dir then
		local file = self:_get_file(entry.node.path)
		if file then
			self.events:emit("file_select", file)
		end
	end
end

---Toggle reviewed status for current file or all files under a directory
function FileTreeBuffer:toggle_reviewed()
	if #self.visible_nodes == 0 then
		return
	end

	local entry = self.visible_nodes[self.current_index]
	if not entry then
		return
	end

	if entry.node.is_dir then
		-- Toggle all files under this directory
		local files_under = self:_get_files_under_dir(entry.node.path)
		if #files_under == 0 then
			return
		end

		-- If any are unreviewed, mark all reviewed; otherwise mark all unreviewed
		local any_unreviewed = false
		for _, f in ipairs(files_under) do
			if not f.reviewed then
				any_unreviewed = true
				break
			end
		end
		local new_reviewed = any_unreviewed

		for _, f in ipairs(files_under) do
			f.reviewed = new_reviewed
			if self.session then
				self.session:set_file_reviewed(f.path, new_reviewed)
			end
		end
		if self.session then
			self.session:save()
		end

		self:_update_visible_nodes()
		self.current_index = math.min(self.current_index, #self.visible_nodes)
		self:render()

		-- Emit toggle for each affected file
		for _, f in ipairs(files_under) do
			self.events:emit("toggle_reviewed", f)
		end

		self:_emit_current_file_select()
	else
		-- Toggle single file
		local file = self:_get_file(entry.node.path)
		if not file then
			return
		end

		file.reviewed = not file.reviewed

		if self.session then
			self.session:set_file_reviewed(file.path, file.reviewed)
			self.session:save()
		end

		self:_update_visible_nodes()
		self.current_index = math.min(self.current_index, #self.visible_nodes)
		self:render()
		self.events:emit("toggle_reviewed", file)

		self:_emit_current_file_select()
	end
end

---Update files list
---@param files File[] New files list
function FileTreeBuffer:set_files(files)
	self.files = files
	self:_update_visible_nodes()

	-- Clamp current index
	if #self.visible_nodes > 0 then
		self.current_index = math.min(self.current_index, #self.visible_nodes)
	else
		self.current_index = 1
	end

	self:render()
end

---Update reviewed status for a file by path
---@param path string File path to update
---@param reviewed boolean New reviewed status
function FileTreeBuffer:update_file_reviewed(path, reviewed)
	for _, file in ipairs(self.files) do
		if file.path == path then
			file.reviewed = reviewed
			self:_update_visible_nodes()
			self.current_index = math.min(self.current_index, math.max(1, #self.visible_nodes))
			self:render()
			return
		end
	end
end

---Get current file (if cursor is on a file node)
---@return File|nil file Current file or nil
function FileTreeBuffer:get_current_file()
	if #self.visible_nodes == 0 then
		return nil
	end

	local entry = self.visible_nodes[self.current_index]
	if entry and not entry.node.is_dir then
		return self:_get_file(entry.node.path)
	end
	return nil
end

---Render the tree
function FileTreeBuffer:render()
	local components = {}

	-- Count reviewed files
	local reviewed_count = 0
	for _, file in ipairs(self.files) do
		if file.reviewed then
			reviewed_count = reviewed_count + 1
		end
	end

	-- Header
	table.insert(components, FileTreeUI.create_header(reviewed_count, #self.files, self.branch))

	-- Tree nodes with separator between sections
	for i, entry in ipairs(self.visible_nodes) do
		-- Insert separator before the reviewed section
		if self.separator_at and i == self.separator_at then
			table.insert(components, FileTreeUI.create_separator())
		end

		local is_current = i == self.current_index
		local node = entry.node

		if node.is_dir then
			table.insert(components, FileTreeUI.create_dir_row(node.name, entry.depth, node.expanded, is_current))
		else
			local file = self:_get_file(node.path)
			local reviewed = file and file.reviewed or false
			table.insert(components, FileTreeUI.create_file_row(node.name, entry.depth, reviewed, is_current))
		end
	end

	self.buffer:render(components)

	-- Position cursor (header is 3 lines, separator adds 1 if present before cursor)
	if #self.visible_nodes > 0 then
		local separator_offset = 0
		if self.separator_at and self.current_index >= self.separator_at then
			separator_offset = 1
		end
		local cursor_line = 3 + self.current_index + separator_offset
		self.buffer:set_cursor(cursor_line, 0)
	end
end

---Show the buffer in the current window
function FileTreeBuffer:show()
	self.buffer:show()
	self:render()
end

---Get buffer handle
---@return number handle Buffer handle
function FileTreeBuffer:get_handle()
	return self.buffer:get_handle()
end

---Close the buffer
function FileTreeBuffer:close()
	self.events:clear()
	self.buffer:close()
end

return FileTreeBuffer
