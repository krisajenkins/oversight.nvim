-- Capture vim.notify calls for the duration of a function.
--
-- The plugin's error paths all route through logger.error, which notifies. A
-- test that deliberately triggers one would otherwise spray the message across
-- the test runner's output; capturing it keeps the run readable and lets the
-- test assert that the user was actually told.

---Run `fn` with vim.notify captured.
---@param fn fun()
---@return string[] messages Notifications raised, in order
return function(fn)
	local original = vim.notify
	local messages = {}

	-- Keep the real signature. A narrower stub makes lua_ls re-infer vim.notify
	-- as one-argument and then flag every `vim.notify(msg, level)` call in the
	-- plugin as passing a redundant parameter.
	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, _level, _opts)
		table.insert(messages, msg)
	end

	local ok, err = pcall(fn)
	vim.notify = original

	if not ok then
		error(err)
	end
	return messages
end
