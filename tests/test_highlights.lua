-- Tests for the plugin's highlight groups

local T = MiniTest.new_set()
local expect = MiniTest.expect

local Highlights = require("oversight.highlights")

T["Highlights"] = MiniTest.new_set()

---Every highlight group the plugin defines, read back from Neovim.
---@return table<string, table> groups Map of group name to its resolved definition
local function oversight_groups()
	Highlights.setup()

	local groups = {}
	for name, def in pairs(vim.api.nvim_get_hl(0, {})) do
		if name:match("^Oversight") then
			groups[name] = def
		end
	end
	return groups
end

-- Regression test. The palette used to be 14 hardcoded One Dark hex values,
-- which ignored the user's colorscheme and did not follow a `:colorscheme`
-- change. Links resolve at draw time, so they track the theme for free.
T["Highlights"]["every group links rather than naming a colour"] = function()
	local groups = oversight_groups()

	expect.equality(vim.tbl_isempty(groups), false)

	for _, def in pairs(groups) do
		expect.no_equality(def.link, nil)
		expect.equality(def.fg, nil)
		expect.equality(def.bg, nil)
	end
end

T["Highlights"]["link targets exist in a bare Neovim"] = function()
	for _, def in pairs(oversight_groups()) do
		-- A group Neovim has never heard of resolves to an empty table.
		local target = vim.api.nvim_get_hl(0, { name = def.link })
		expect.equality(vim.tbl_isempty(target), false)
	end
end

-- `default = true` is the API form of `hi default link`, so a user who styles
-- one of these before setup() runs keeps their choice.
T["Highlights"]["does not clobber a user's own definition"] = function()
	vim.api.nvim_set_hl(0, "OversightCommentIssue", { fg = "#ff00ff" })

	Highlights.setup()

	local def = vim.api.nvim_get_hl(0, { name = "OversightCommentIssue" })
	expect.equality(def.fg, tonumber("ff00ff", 16))
	expect.equality(def.link, nil)

	-- Restore the default so this test is order-independent: the two tests
	-- above assert that every group is a link, and highlight state is global
	-- to the Neovim instance running the suite.
	vim.api.nvim_set_hl(0, "OversightCommentIssue", { link = "DiagnosticError" })
end

return T
