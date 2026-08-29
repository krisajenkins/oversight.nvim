-- Lua source that builds a throwaway git repository inside a child Neovim.
--
--     local git_repo = require("tests.helpers.git_repo")
--     child.lua(git_repo({ "printf 'one\\n' > a.txt", "git add -A" }))
--     child.lua("make_repo()")
--
-- The caller supplies the shell that fills the repository in; everything around
-- it — a neutral git configuration, the runtimepath fix, the chdir — is the
-- same every time and lives here.
--
-- The neutral configuration is not tidiness. The child inherits this process's
-- environment, so without it the developer's own git config reaches the
-- assertions; see the note at the top of tests/test_vcs_hermetic.lua.

---@param commands string[] Shell lines, run in order inside the fresh repository
---@return string source Lua source defining `_G.make_repo()`, which returns the path
return function(commands)
	local prelude = {
		"export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null",
		"export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.com",
		"export GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.com",
		"git init --quiet --initial-branch=main",
	}

	return string.format(
		[[
function _G.make_repo()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")

	local script = table.concat(
		vim.list_extend({ "cd " .. vim.fn.shellescape(dir) }, vim.list_extend(%s, %s)),
		"\n"
	)
	local out = vim.fn.system({ "bash", "-euo", "pipefail", "-c", script })
	assert(vim.v.shell_error == 0, "repo setup failed: " .. out)

	-- scripts/minimal_init.lua puts `deps/plenary.nvim` on the runtimepath
	-- relatively, so changing directory would make `require("plenary.job")`
	-- fail. Pin the entries to absolute paths before moving.
	local project = vim.fn.getcwd()
	for _, path in ipairs({ project, project .. "/deps/plenary.nvim", project .. "/deps/mini.nvim" }) do
		vim.opt.runtimepath:append(path)
	end

	vim.cmd("cd " .. vim.fn.fnameescape(dir))
	return dir
end
]],
		vim.inspect(prelude),
		vim.inspect(commands)
	)
end
