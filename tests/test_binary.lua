-- Tests for binary-file detection.
--
-- The interesting case is the one that used to be wrong everywhere: browse mode
-- scanned `readfile` output for a NUL byte, and never found one, because Vim
-- represents a NUL inside a line as a newline. The last case here is the guard
-- against writing that check again.

local Binary = require("oversight.lib.binary")

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Binary"] = MiniTest.new_set()

---Write bytes to a temp file and hand back the path, plus a cleanup.
---@param bytes string
---@return string path
---@return fun() cleanup
local function tempfile(bytes)
	local path = vim.fn.tempname()
	local fd = assert(io.open(path, "wb"))
	fd:write(bytes)
	fd:close()
	return path, function()
		vim.fn.delete(path)
	end
end

T["Binary"]["finds a NUL byte in a string"] = function()
	expect.equality(Binary.has_null("plain text"), false)
	expect.equality(Binary.has_null("with a \0 in it"), true)
end

T["Binary"]["scans lines that came off a pipe"] = function()
	expect.equality(Binary.lines_are_binary({ "one", "two" }), false)
	expect.equality(Binary.lines_are_binary({ "one", "tw\0o" }), true)
end

-- Only the head of a file is sampled, so a NUL past the sample is not found.
-- That is the trade, and it is deliberate: a video should not be read into
-- memory in order to decide not to display it.
T["Binary"]["only samples the head of a long file"] = function()
	local padding = string.rep("x", Binary.SAMPLE_BYTES + 10)

	expect.equality(Binary.lines_are_binary({ padding, "\0" }), false)
end

T["Binary"]["reads a real file's bytes"] = function()
	local text, clean_text = tempfile("hello\nworld\n")
	local blob, clean_blob = tempfile("\x00\x01\x02BINARY\xff")

	expect.equality(Binary.file_is_binary(text), false)
	expect.equality(Binary.file_is_binary(blob), true)

	clean_text()
	clean_blob()
end

T["Binary"]["says no about a file that is not there"] = function()
	expect.equality(Binary.file_is_binary(vim.fn.tempname()), false)
end

-- The regression this module exists for. `readfile` replaces every NUL with a
-- newline, in binary mode as well as text mode, so its output cannot be asked
-- whether the file was binary — the answer is always no.
T["Binary"]["is why lines from readfile cannot answer the question"] = function()
	local path, cleanup = tempfile("\x00\x01\x02BINARY\xff")

	local lines = vim.fn.readfile(path)
	expect.equality(Binary.lines_are_binary(lines), false)
	expect.equality(Binary.file_is_binary(path), true)

	cleanup()
end

return T
