-- Tests for the shared CLI builder (lib/cli.lua)
--
-- The git and jj CLI builders are both thin wrappers over this module, so its
-- process-spawning behaviour is tested once here rather than in each backend.

local T = MiniTest.new_set()
local expect = MiniTest.expect

local Cli = require("oversight.lib.cli")

T["Cli"] = MiniTest.new_set()

-- Regression test. plenary's Job treats any non-nil `env` table as the COMPLETE
-- child environment, and an empty Lua table is truthy — so passing the builder's
-- always-present `env = {}` handed every git/jj call an empty environment. git
-- then silently ignored ~/.gitconfig and jj ignored ~/.config/jj/config.toml.
T["Cli"]["inherits the parent environment when none is set"] = function()
	local result = Cli.new("sh"):arg("-c"):arg('printf %s "$HOME"'):call()

	expect.equality(result.success, true)
	expect.equality(result.stdout, vim.env.HOME)
	expect.equality(result.stdout ~= "", true)
end

T["Cli"]["env() variables reach the child"] = function()
	local result = Cli.new("sh"):arg("-c"):arg('printf %s "$OVERSIGHT_TEST"'):env("OVERSIGHT_TEST", "hello"):call()

	expect.equality(result.success, true)
	expect.equality(result.stdout, "hello")
end

T["Cli"]["a nonzero exit is reported as failure"] = function()
	local result = Cli.new("sh"):arg("-c"):arg("exit 3"):call()

	expect.equality(result.success, false)
	expect.equality(result.exit_code, 3)
end

---Run `fn` with vim.notify silenced, returning the notifications it emitted.
---@param fn function
---@return table[] notifications List of { msg = string, level = number }
local function capture_notifications(fn)
	local original = vim.notify
	local captured = {}
	vim.notify = function(msg, level)
		table.insert(captured, { msg = msg, level = level })
	end
	local ok, err = pcall(fn)
	vim.notify = original
	if not ok then
		error(err)
	end
	return captured
end

-- A missing binary used to reach Job:new as a bare name, which raises
-- "<cmd>: Executable not found" with a traceback that we handed back as stderr.
T["Cli"]["a missing executable fails cleanly rather than raising"] = function()
	local result
	local notifications = capture_notifications(function()
		result = Cli.new("oversight-no-such-binary"):arg("--version"):call()
	end)

	expect.equality(result.success, false)
	expect.equality(result.exit_code, -1)
	expect.equality(result.stderr:match("not found on PATH") ~= nil, true)

	-- The user is told, rather than left with an empty-looking result.
	expect.equality(#notifications, 1)
	expect.equality(notifications[1].level, vim.log.levels.ERROR)
end

-- Regression test for the 5s default. plenary's Job:sync() times out after
-- 5000ms unless given one, so a command slower than that used to come back as a
-- failure with a plenary stack trace in stderr and no notification — a slow
-- `git diff` rendered as an empty diff. The sleep here is deliberately just
-- past the old default: long enough to prove the timeout was raised, short
-- enough not to dominate the suite.
T["Cli"]["survives a command slower than plenary's 5s default"] = function()
	local result = Cli.new("sh"):arg("-c"):arg("sleep 6 && printf slow"):call()

	expect.equality(result.success, true)
	expect.equality(result.stdout, "slow")
end

return T
