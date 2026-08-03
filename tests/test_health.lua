-- Tests for :checkhealth oversight

local T = MiniTest.new_set()
local expect = MiniTest.expect

T["Health"] = MiniTest.new_set()

---Run `M.check()` against a stubbed vim.health, returning the calls it made.
---The health module feature-detects the API at require time, so it is reloaded
---inside the stub.
---@param api_names string[] Names to expose on the stub (e.g. {"report_ok"})
---@return table[] calls List of { fn = string, msg = string }
local function check_with_stub(api_names)
	local original_health = vim.health
	local original_module = package.loaded["oversight.health"]

	local calls = {}
	local stub = {}
	for _, name in ipairs(api_names) do
		stub[name] = function(msg)
			table.insert(calls, { fn = name, msg = msg })
		end
	end
	vim.health = stub

	package.loaded["oversight.health"] = nil
	local ok, err = pcall(function()
		require("oversight.health").check()
	end)

	vim.health = original_health
	package.loaded["oversight.health"] = original_module

	if not ok then
		error(err)
	end
	return calls
end

local MODERN = { "start", "ok", "warn", "error", "info" }
local LEGACY = { "report_start", "report_ok", "report_warn", "report_error", "report_info" }

T["Health"]["runs against the Neovim 0.10+ API"] = function()
	local calls = check_with_stub(MODERN)

	expect.equality(#calls > 0, true)
	expect.equality(calls[1].fn, "start")
	expect.equality(calls[1].msg, "oversight")
end

-- Regression test. The module called vim.health.start directly, but that name
-- only exists on Neovim 0.10+ — so :checkhealth raised on 0.9, the oldest
-- version the README, vimdoc and this very check all claim to support.
T["Health"]["falls back to the report_* API on Neovim 0.9"] = function()
	local calls = check_with_stub(LEGACY)

	expect.equality(#calls > 0, true)
	expect.equality(calls[1].fn, "report_start")
	expect.equality(calls[1].msg, "oversight")
end

T["Health"]["reports the discovered git version and path"] = function()
	local calls = check_with_stub(MODERN)

	local git_line = nil
	for _, call in ipairs(calls) do
		if call.msg:match("^git ") then
			git_line = call.msg
		end
	end

	-- git is provided by the flake, so it is always present under `make test`.
	expect.no_equality(git_line, nil)
	expect.equality(tostring(git_line):match("%d+%.%d+%.%d+") ~= nil, true)
end

return T
