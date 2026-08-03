-- Shared scaffolding for tests that drive a child Neovim.
--
--     local child, child_set = require("tests.helpers.child")()
--     local T = child_set()
--
-- `child_set` builds a MiniTest set whose pre_case restarts the child at fixed
-- dimensions with the plugin loaded, and whose post_once stops it. Screenshot
-- comparisons depend on those dimensions, so they live here rather than in each
-- file: a test that forgets to set them produces a reference nobody can
-- reproduce.
--
-- Extra pre_case work is *appended* to the standard block, never replaces it:
--
--     local T = child_set({
--         columns = 120,
--         pre_case = function()
--             child.lua("...")
--         end,
--     })

-- The child's own default is 24x80; 30x100 leaves room for the two-panel
-- layouts without wrapping the paths in the file list.
local DEFAULT_LINES = 30
local DEFAULT_COLUMNS = 100

---@class ChildSetOpts
---@field lines? number Terminal height (default 30)
---@field columns? number Terminal width (default 100)
---@field pre_case? fun() Extra setup, run after the standard block

---Create a child Neovim and a set factory bound to it.
---@return table child The MiniTest child Neovim object
---@return fun(opts?: ChildSetOpts): table new_set
return function()
	local child = MiniTest.new_child_neovim()

	---@param opts? ChildSetOpts
	---@return table set
	local function child_set(opts)
		opts = opts or {}

		return MiniTest.new_set({
			hooks = {
				pre_case = function()
					child.restart({ "-u", "scripts/minimal_init.lua" })
					child.o.lines = opts.lines or DEFAULT_LINES
					child.o.columns = opts.columns or DEFAULT_COLUMNS

					-- minimal_init only wires up the test dependencies; the
					-- plugin itself is loaded from the parent's working
					-- directory, which the child inherits.
					child.lua([[
						vim.cmd("set rtp+=.")
						require("oversight").setup()
					]])

					if opts.pre_case then
						opts.pre_case()
					end
				end,
				post_once = child.stop,
			},
		})
	end

	return child, child_set
end
