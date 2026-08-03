-- Tests for the shared CLI builder (lib/cli.lua)
--
-- The git and jj CLI builders are both thin wrappers over this module, so its
-- process-spawning behaviour is tested once here rather than in each backend.

local capture_notifications = require("tests.helpers.notify")

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

-- Regression test for plenary's 5s default. Job:sync() gives up after 5000ms
-- unless told otherwise, so any command slower than that came back as a failure
-- with a plenary stack trace in stderr — a slow `git diff` rendered as an empty
-- diff. Asserting the constant costs nothing; the behaviour itself is covered by
-- the timeout tests below, which override it rather than sleeping past 5s.
T["Cli"]["waits a minute by default, not plenary's five seconds"] = function()
	expect.equality(Cli.timeout_ms, 60000)
end

T["Cli"]["timeout() overrides the wait for one command"] = function()
	local builder = Cli.new("sh"):timeout(250)

	expect.equality(builder.timeout_ms, 250)
	-- The class default is untouched, so the override really is per-builder.
	expect.equality(Cli.timeout_ms, 60000)
end

T["Cli"]["a timed-out command fails with a legible message"] = function()
	local result
	local notifications = capture_notifications(function()
		result = Cli.new("sh"):arg("-c"):arg("sleep 30"):timeout(200):call()
	end)

	expect.equality(result.success, false)
	expect.equality(result.exit_code, -1)

	-- WARN, not ERROR: a slow repository is not a broken one.
	expect.equality(#notifications, 1)
	expect.equality(notifications[1].level, vim.log.levels.WARN)
	expect.equality(tostring(notifications[1].msg):find("timed out", 1, true) ~= nil, true)
end

-- ---------------------------------------------------------------------------
-- call_async
-- ---------------------------------------------------------------------------
--
-- These run in a child Neovim, and they have to. Waiting for an async result
-- means `vim.wait` with the event loop live, and mini.test schedules every case
-- up front with `vim.schedule` (mini/test.lua, MiniTest.execute) — so a
-- non-fast `vim.wait` inside a case flushes that queue and starts the *following*
-- cases nested inside the current one. The outer case then finishes into a
-- runner that has moved on, and its result is dropped: no pass, no fail, no
-- warning. plenary's own Job:wait dodges this by passing `fast_only = true`,
-- which is why the synchronous tests above are safe and these are not.
--
-- In the child, the waiting happens outside the runner entirely, and the parent
-- blocks on a plain RPC call.

local child, child_set = require("tests.helpers.child")()

T["Cli async"] = child_set()

---Run a builder's `call_async` to completion inside the child.
---@param builder string Lua source for the CliBuilder, e.g. `Cli.new("sh")...`
---@return table outcome { done, result, returned_early, notifications }
local function run_in_child(builder)
	return child.lua_get(string.format(
		[[(function()
			local Cli = require("oversight.lib.cli")
			local async = require("plenary.async")

			local notifications = {}
			local original_notify = vim.notify
			vim.notify = function(msg, level)
				table.insert(notifications, { msg = msg, level = level })
			end

			local result, done = nil, false
			async.run(function()
				result = %s:call_async()
				done = true
			end)

			-- Captured before waiting: a call that genuinely yields has already
			-- handed control back here while the command is still running.
			local returned_early = not done

			vim.wait(10000, function() return done end, 10)
			vim.notify = original_notify

			return {
				done = done,
				result = result,
				returned_early = returned_early,
				notifications = notifications,
			}
		end)()]],
		builder
	))
end

T["Cli async"]["returns the same result shape as call()"] = function()
	local outcome = run_in_child([[Cli.new("sh"):arg("-c"):arg("printf hello")]])

	expect.equality(outcome.done, true)
	expect.equality(outcome.result.success, true)
	expect.equality(outcome.result.exit_code, 0)
	expect.equality(outcome.result.stdout, "hello")
end

-- Regression test. call_async used to wrap the blocking call() in async.wrap,
-- so it held the editor for exactly as long as call() did — it satisfied the
-- type but delivered none of the benefit, and nothing warned the next caller.
T["Cli async"]["yields instead of blocking the editor"] = function()
	local outcome = run_in_child([[Cli.new("sh"):arg("-c"):arg("sleep 0.5")]])

	expect.equality(outcome.done, true)
	expect.equality(outcome.returned_early, true)
end

T["Cli async"]["reports a nonzero exit as failure"] = function()
	local outcome = run_in_child([[Cli.new("sh"):arg("-c"):arg("exit 4")]])

	expect.equality(outcome.result.success, false)
	expect.equality(outcome.result.exit_code, 4)
end

T["Cli async"]["a missing executable fails cleanly"] = function()
	local outcome = run_in_child([[Cli.new("oversight-no-such-binary"):arg("--version")]])

	expect.equality(outcome.result.success, false)
	expect.equality(outcome.result.exit_code, -1)
	expect.equality(#outcome.notifications, 1)
	expect.equality(outcome.notifications[1].level, vim.log.levels.ERROR)
end

-- The timeout timer and the job's exit callback race each other, and resuming
-- an already-resumed coroutine raises. This exercises the timer winning; the
-- `finished` guard is what stops the loser resuming a second time.
T["Cli async"]["gives up on a command that outlives its timeout"] = function()
	local outcome = run_in_child([[Cli.new("sh"):arg("-c"):arg("sleep 30"):timeout(200)]])

	expect.equality(outcome.done, true)
	expect.equality(outcome.result.success, false)
	expect.equality(outcome.result.exit_code, -1)
	expect.equality(outcome.result.stderr:find("timed out", 1, true) ~= nil, true)

	expect.equality(#outcome.notifications, 1)
	expect.equality(outcome.notifications[1].level, vim.log.levels.WARN)

	-- The killed job still delivers an exit event. If the guard were missing it
	-- would resume a dead coroutine, and the child would be left broken — so
	-- give it a moment and then check the child is still answering.
	child.lua([[vim.wait(300)]])
	expect.equality(child.lua_get("1 + 1"), 2)
end

return T
