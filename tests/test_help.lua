-- Keeps the help overlay honest about the keys that actually exist.
--
-- Keybindings live in four places (see the Keybindings section of CLAUDE.md).
-- Only one of them is executable, so only one can be the source of truth: the
-- buffers' `_setup_mappings` methods plus the tab-level maps in
-- buffers/review/init.lua and buffers/browse/init.lua. This file checks the help
-- overlay against that truth by reading the maps back off the live buffers, so
-- adding a keybinding without documenting it fails the suite.
--
-- It cannot check README.md or doc/oversight.txt — those are prose, and parsing
-- them would test the parser more than the docs. They stay a manual step.
--
-- Runs in a child Neovim: it opens real windows and needs `vim.wait` with the
-- event loop live, which silently abandons a mini.test case in-process. See
-- tests/CLAUDE.md.

local child, child_set = require("tests.helpers.child")()
local expect = MiniTest.expect

local T = child_set()

T["Help"] = MiniTest.new_set()

-- A key's on-screen spelling. The help text writes keys in a column, joined with
-- "/" when several share a description, so this maps a mapping's `lhs` to the
-- atom expected to appear there.
local KEY_SPELLING = [[
local KEY_SPELLING = {
	["<C-D>"] = "Ctrl-d",
	["<C-U>"] = "Ctrl-u",
	["<C-F>"] = "Ctrl-f",
	["<C-B>"] = "Ctrl-b",
	["<CR>"] = "Enter",
	["<Tab>"] = "Tab",
	["<Down>"] = "Down",
	["<Up>"] = "Up",
	["<Right>"] = "Right",
	["<Left>"] = "Left",
}

---Pull the key column out of the help text and expand it into single keys.
---A line looks like "  Ctrl-d/u    Half page down/up"; the atoms are the
---slash-separated parts, with a bare letter after a Ctrl- part inheriting the
---prefix so "Ctrl-d/u" yields Ctrl-d and Ctrl-u rather than Ctrl-d and u.
---@param text string[]
---@return table<string, boolean>
local function documented_keys(text)
	local documented = {}
	for _, line in ipairs(text) do
		local column = line:match("^  (%S+)%s%s+%S")
		if column then
			local ctrl = false
			for part in column:gmatch("[^/]+") do
				if part:match("^Ctrl%-") then
					ctrl = true
				elseif ctrl and #part == 1 then
					part = "Ctrl-" .. part
				end
				documented[part] = true
			end
		end
	end
	return documented
end

---Every key bound to a real action in a buffer. Maps without a description are
---the no-op guards that stop the panels being edited, not user-facing keys.
---@param handle number
---@return table<string, boolean>
local function bound_keys(handle)
	local bound = {}
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(handle, "n")) do
		if map.desc and map.desc ~= "" then
			bound[map.lhs] = true
		end
	end
	return bound
end

---Keys that are bound but never appear in the help text.
---@param panels table<string, number> Label to buffer handle
---@param text string[]
---@return string[]
local function undocumented(panels, text)
	local documented = documented_keys(text)
	local missing = {}
	for label, handle in pairs(panels) do
		for lhs in pairs(bound_keys(handle)) do
			local spelling = KEY_SPELLING[lhs] or lhs
			if not documented[spelling] then
				table.insert(missing, label .. ":" .. lhs)
			end
		end
	end
	table.sort(missing)
	return missing
end

-- Each child.lua call is its own chunk, so the entry point has to be reachable
-- from the next one. The locals above stay upvalues of this closure.
_G.undocumented = undocumented
]]

-- A repository with committed history and uncommitted changes on top, so review
-- mode has something to show.
local MAKE_REPO = require("tests.helpers.git_repo")({
	"mkdir -p src",
	"printf 'one\\ntwo\\n' > src/kept.lua",
	"git add -A",
	"git commit --quiet -m init",
	"printf 'one\\nTWO\\n' > src/kept.lua",
})

---Open a mode, focus each of its panels so the tab-level maps install, and
---return the keys it binds but never documents.
---@param mode "review"|"browse"
---@return string[] missing
local function undocumented_in(mode)
	child.lua(KEY_SPELLING)
	child.lua(MAKE_REPO)
	return child.lua_get(string.format(
		[[(function()
		make_repo()
		require("oversight").setup()
		local Help = require("oversight.buffers.help")
		local view, text, panels
		if %q == "review" then
			view = require("oversight.buffers.review").open()
			text = Help.REVIEW_HELP_TEXT
			-- Review mode has three panels, not two: the diff is a pair of
			-- buffers with Neovim's own diff between them, and each side carries
			-- its own copy of the map set.
			panels = {
				file_list = view.file_list:get_handle(),
				diff_base = view.diff_view.old:get_handle(),
				diff_working = view.diff_view.new:get_handle(),
			}
		else
			view = require("oversight.buffers.browse").open()
			text = Help.BROWSE_HELP_TEXT
			panels = {
				file_tree = view.file_tree:get_handle(),
				file_view = view.file_view:get_handle(),
			}
		end
		assert(view, "failed to open %s mode")

		-- The tab-level maps (Tab, {, }, y, X, R, ?, q) install on BufEnter, so a
		-- panel that has never been focused is missing them. Visit all of them.
		for _, handle in pairs(panels) do
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(win) == handle then
					vim.api.nvim_set_current_win(win)
					vim.cmd("doautocmd BufEnter")
				end
			end
		end
		return undocumented(panels, text)
	end)()]],
		mode,
		mode
	))
end

T["Help"]["documents every key review mode binds"] = function()
	expect.equality(undocumented_in("review"), {})
end

-- Browse mode used to show the review help, which talks about hunks that do not
-- exist here and omits `l`/`h`. This is the guard against it regressing.
T["Help"]["documents every key browse mode binds"] = function()
	expect.equality(undocumented_in("browse"), {})
end

T["Help"]["gives each mode its own text"] = function()
	child.lua([[_G.Help = require("oversight.buffers.help")]])
	local review = table.concat(child.lua_get([[_G.Help.REVIEW_HELP_TEXT]]), "\n")
	local browse = table.concat(child.lua_get([[_G.Help.BROWSE_HELP_TEXT]]), "\n")

	expect.equality(review:find("Review Mode", 1, true) ~= nil, true)
	expect.equality(browse:find("Browse Mode", 1, true) ~= nil, true)

	-- Hunks are a diff-view concept; browse mode has no diffs to step through.
	expect.equality(review:find("hunk", 1, true) ~= nil, true)
	expect.equality(browse:find("hunk", 1, true), nil)
end

-- The comment dialog is a floating window rather than a panel, so the map-
-- reading check above never sees it. `1`-`3` set the comment type directly and
-- went undocumented in both surfaces until this audit.
T["Help"]["documents the comment dialog type shortcuts"] = function()
	child.lua([[_G.Help = require("oversight.buffers.help")]])
	for _, name in ipairs({ "REVIEW_HELP_TEXT", "BROWSE_HELP_TEXT" }) do
		local text = table.concat(child.lua_get("_G.Help." .. name), "\n")
		expect.equality(text:find("1/2/3", 1, true) ~= nil, true)
		expect.equality(text:find("Ctrl-t/Tab", 1, true) ~= nil, true)
	end
end

return T
