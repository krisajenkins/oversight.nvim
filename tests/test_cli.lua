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

return T
