-- Diff parsing module
-- Parses unified diff output and converts to side-by-side format

local logger = require("tuicr.logger")

local M = {}

---@class DiffLine
---@field line_no_old number|nil Line number in old file
---@field line_no_new number|nil Line number in new file
---@field content_old string Content for old side
---@field content_new string Content for new side
---@field type "add"|"delete"|"context"|"empty" Line type

---@class DiffHunk
---@field header string Hunk header (@@ ... @@)
---@field old_start number Starting line in old file
---@field old_count number Number of lines in old file
---@field new_start number Starting line in new file
---@field new_count number Number of lines in new file
---@field lines DiffLine[] Diff lines

---@class FileDiff
---@field path string File path
---@field old_path string|nil Old path (for renames)
---@field status string Git status (A, M, D, R)
---@field hunks DiffHunk[] Diff hunks
---@field is_binary boolean Whether file is binary

---Parse hunk header to extract line numbers
---@param header string Hunk header line
---@return number old_start, number old_count, number new_start, number new_count
local function parse_hunk_header(header)
	-- Format: @@ -old_start,old_count +new_start,new_count @@
	local old_start, old_count, new_start, new_count = header:match("^@@%s+%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s+@@")

	old_start = tonumber(old_start) or 1
	old_count = tonumber(old_count) or 1
	new_start = tonumber(new_start) or 1
	new_count = tonumber(new_count) or 1

	return old_start, old_count, new_start, new_count
end

---Parse unified diff into side-by-side format
---@param diff_lines string[] Lines from git diff output
---@return DiffHunk[] hunks Parsed hunks
function M.parse_unified_diff(diff_lines)
	local hunks = {}
	local current_hunk = nil
	local old_line_no = 0
	local new_line_no = 0

	for _, line in ipairs(diff_lines) do
		if line:match("^@@") then
			-- New hunk
			if current_hunk then
				table.insert(hunks, current_hunk)
			end

			local old_start, old_count, new_start, new_count = parse_hunk_header(line)
			current_hunk = {
				header = line,
				old_start = old_start,
				old_count = old_count,
				new_start = new_start,
				new_count = new_count,
				lines = {},
			}
			old_line_no = old_start
			new_line_no = new_start
		elseif current_hunk then
			local prefix = line:sub(1, 1)
			local content = line:sub(2)

			if prefix == "-" then
				-- Deleted line
				table.insert(current_hunk.lines, {
					line_no_old = old_line_no,
					line_no_new = nil,
					content_old = content,
					content_new = "",
					type = "delete",
				})
				old_line_no = old_line_no + 1
			elseif prefix == "+" then
				-- Added line
				table.insert(current_hunk.lines, {
					line_no_old = nil,
					line_no_new = new_line_no,
					content_old = "",
					content_new = content,
					type = "add",
				})
				new_line_no = new_line_no + 1
			elseif prefix == " " then
				-- Context line
				table.insert(current_hunk.lines, {
					line_no_old = old_line_no,
					line_no_new = new_line_no,
					content_old = content,
					content_new = content,
					type = "context",
				})
				old_line_no = old_line_no + 1
				new_line_no = new_line_no + 1
			end
			-- Note: prefix == "\\" ("No newline at end of file") is intentionally ignored
		end
	end

	if current_hunk then
		table.insert(hunks, current_hunk)
	end

	return hunks
end

---Convert unified diff lines to aligned side-by-side format
---@param hunks DiffHunk[] Parsed hunks
---@return DiffLine[] lines Aligned lines for side-by-side display
function M.to_side_by_side(hunks)
	local result = {}

	for _, hunk in ipairs(hunks) do
		-- Add hunk header as a special line
		table.insert(result, {
			line_no_old = nil,
			line_no_new = nil,
			content_old = hunk.header,
			content_new = "",
			type = "hunk_header",
		})

		-- Process lines, aligning deletions with additions
		local i = 1
		while i <= #hunk.lines do
			local line = hunk.lines[i]

			if line.type == "delete" then
				-- Look for matching additions
				local deletions = { line }
				local j = i + 1

				-- Collect consecutive deletions
				while j <= #hunk.lines and hunk.lines[j].type == "delete" do
					table.insert(deletions, hunk.lines[j])
					j = j + 1
				end

				-- Collect consecutive additions
				local additions = {}
				while j <= #hunk.lines and hunk.lines[j].type == "add" do
					table.insert(additions, hunk.lines[j])
					j = j + 1
				end

				-- Pair deletions with additions
				local max_len = math.max(#deletions, #additions)
				for k = 1, max_len do
					local del = deletions[k]
					local add = additions[k]

					if del and add then
						-- Paired change
						table.insert(result, {
							line_no_old = del.line_no_old,
							line_no_new = add.line_no_new,
							content_old = del.content_old,
							content_new = add.content_new,
							type = "change",
						})
					elseif del then
						-- Just deletion
						table.insert(result, {
							line_no_old = del.line_no_old,
							line_no_new = nil,
							content_old = del.content_old,
							content_new = "",
							type = "delete",
						})
					elseif add then
						-- Just addition
						table.insert(result, {
							line_no_old = nil,
							line_no_new = add.line_no_new,
							content_old = "",
							content_new = add.content_new,
							type = "add",
						})
					end
				end

				i = j
			elseif line.type == "add" then
				-- Standalone addition (shouldn't happen often due to above logic)
				table.insert(result, {
					line_no_old = nil,
					line_no_new = line.line_no_new,
					content_old = "",
					content_new = line.content_new,
					type = "add",
				})
				i = i + 1
			else
				-- Context line
				table.insert(result, line)
				i = i + 1
			end
		end
	end

	return result
end

---Get diff for a specific file
---@param repo_root string Repository root directory
---@param file_path string File path relative to repo root
---@return FileDiff|nil diff File diff or nil on error
function M.get_file_diff(repo_root, file_path)
	local git = require("tuicr.lib.git.cli")

	local result = git.diff():arg("HEAD"):arg("--"):arg(file_path):cwd(repo_root):call()

	if not result.success then
		logger.error("Failed to get diff for %s: %s", file_path, result.stderr)
		return nil
	end

	if result.stdout == "" then
		-- No changes for this file
		return {
			path = file_path,
			old_path = nil,
			status = "M",
			hunks = {},
			is_binary = false,
		}
	end

	-- Check for binary file
	if result.stdout:match("Binary files") then
		return {
			path = file_path,
			old_path = nil,
			status = "M",
			hunks = {},
			is_binary = true,
		}
	end

	local lines = vim.split(result.stdout, "\n")
	local hunks = M.parse_unified_diff(lines)

	return {
		path = file_path,
		old_path = nil,
		status = "M",
		hunks = hunks,
		is_binary = false,
	}
end

---Get all file diffs in the repository
---@param repo table Repository instance
---@return FileDiff[] diffs List of file diffs
function M.get_all_diffs(repo)
	local files = repo:get_changed_files()
	local diffs = {}

	for _, file in ipairs(files) do
		local diff = M.get_file_diff(repo:get_root(), file.path)
		if diff then
			diff.status = file.status
			diff.old_path = file.old_path
			table.insert(diffs, diff)
		end
	end

	return diffs
end

return M
