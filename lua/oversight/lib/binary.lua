-- Binary-file detection, shared by review and browse mode.
--
-- The obvious test — scan the lines for a NUL byte — does not work on anything
-- that came through `vim.fn.readfile`. Vim represents a NUL *inside* a line as
-- a newline internally, so readfile hands back "\n" where the file had "\0",
-- in binary mode as well as text mode. A `line:find("%z")` over readfile output
-- therefore never matches, whatever the file contains.
--
-- So the working copy is sniffed by reading raw bytes off disk, and content
-- that arrived down a pipe (a file at the base revision) is checked as the
-- string it still is.

local M = {}

---How much of a file to sniff. Enough to catch a binary header without reading
---a gigabyte of video into memory to decide not to show it.
M.SAMPLE_BYTES = 8192

---Does this text hold a NUL byte?
---@param text string
---@return boolean
function M.has_null(text)
	return text:find("\0", 1, true) ~= nil
end

---Do any of these lines hold a NUL byte?
---
---Only meaningful for lines that came from a command's stdout. Lines read with
---`readfile` cannot answer this question — see the note at the top.
---@param lines string[]
---@return boolean
function M.lines_are_binary(lines)
	local sampled = 0
	for _, line in ipairs(lines) do
		if M.has_null(line) then
			return true
		end
		sampled = sampled + #line + 1
		if sampled >= M.SAMPLE_BYTES then
			return false
		end
	end
	return false
end

---Is the file at this path binary?
---@param path string Absolute path
---@return boolean binary False when the file cannot be opened, which the caller
---will discover for itself when it tries to read it
function M.file_is_binary(path)
	local fd = io.open(path, "rb")
	if not fd then
		return false
	end
	local chunk = fd:read(M.SAMPLE_BYTES)
	fd:close()
	return chunk ~= nil and M.has_null(chunk)
end

return M
