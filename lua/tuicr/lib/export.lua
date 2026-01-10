-- Markdown export for review feedback

local M = {}

---Convert a session to markdown format optimized for LLM feedback
---@param session ReviewSession Review session
---@param repo GitRepository Git repository
---@return string markdown Markdown string
function M.to_markdown(session, repo)
	local lines = {}

	-- Header
	local repo_name = vim.fn.fnamemodify(repo:get_root(), ":t")
	local commit = repo:get_head():sub(1, 8)
	table.insert(lines, string.format("# Code Review: %s @ %s", repo_name, commit))
	table.insert(lines, "")

	-- Group comments by file
	local comments_by_file = {}
	for _, comment in ipairs(session.comments) do
		comments_by_file[comment.file] = comments_by_file[comment.file] or {}
		table.insert(comments_by_file[comment.file], comment)
	end

	-- Sort files alphabetically
	local sorted_files = {}
	for file, _ in pairs(comments_by_file) do
		table.insert(sorted_files, file)
	end
	table.sort(sorted_files)

	-- Output comments per file
	for _, file in ipairs(sorted_files) do
		local file_comments = comments_by_file[file]

		-- Sort comments by line number
		table.sort(file_comments, function(a, b)
			local line_a = a.line or 0
			local line_b = b.line or 0
			return line_a < line_b
		end)

		table.insert(lines, string.format("## %s", file))
		table.insert(lines, "")

		for _, comment in ipairs(file_comments) do
			-- Format location
			local location
			if comment.line then
				if comment.side == "old" then
					location = string.format("Line ~%d (deleted)", comment.line)
				else
					location = string.format("Line %d", comment.line)
				end
			else
				location = "(file-level)"
			end

			-- Format type label
			local type_label = comment.type:upper()

			table.insert(lines, string.format("**[%s]** %s", type_label, location))
			table.insert(lines, "")

			-- Indent comment text
			for _, text_line in ipairs(vim.split(comment.text, "\n")) do
				table.insert(lines, "> " .. text_line)
			end
			table.insert(lines, "")
		end
	end

	return table.concat(lines, "\n")
end

---Export session to a file
---@param session ReviewSession Review session
---@param repo GitRepository Git repository
---@param output_path string Output file path
---@return boolean success True if export succeeded
function M.to_file(session, repo, output_path)
	local markdown = M.to_markdown(session, repo)
	local lines = vim.split(markdown, "\n")

	local ok = pcall(function()
		vim.fn.writefile(lines, output_path)
	end)

	return ok
end

return M
