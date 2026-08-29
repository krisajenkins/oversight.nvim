-- Base VCS backend class
-- Provides shared logic for all VCS backends (git, jj, etc.)

local M = {}

---Turn a command's stdout into buffer lines.
---
---The two sides of the diff view have to agree on where the lines fall, and
---they arrive by different routes: the working copy through `vim.fn.readfile`,
---the base revision through a CLI's stdout. `lib/cli.lua` builds that stdout
---the way plenary hands it over — the process's output split on newlines and
---rejoined with them, with no trailing one — so a plain split agrees with
---`readfile` both for a file that ends in a newline and for one that does not.
---
---The single case the string form cannot express is an empty file versus a file
---holding one empty line: both arrive as "". Empty wins, because that is what a
---file which does not exist at the base revision looks like, and that case is
---far commoner than a file whose entire content is a newline.
---@param result CliResult The finished command
---@param absent boolean True when the failure means "no such path at the base"
---@return string[]|nil lines File lines, {} when absent or empty, nil on error
function M.file_content_lines(result, absent)
	if absent then
		return {}
	end
	if not result.success then
		return nil
	end
	if result.stdout == "" then
		return {}
	end
	return vim.split(result.stdout, "\n", { plain = true })
end

---Create a backend class with shared behavior.
---Returns a new class table that inherits from BackendClass via __index,
---without mutating the original.
---
---The returned class provides: new(), instance(), get_root(), get_ref(),
---get_branch(), has_changes(), read_file(), clear_cache(), get_head.
---
---The backend must implement:
---  .new(dir) → instance|nil  (sets self.type, self.root, self.ref, self.branch)
---  :refresh()                 (re-fetches ref and branch)
---  :get_changed_files()       (returns VcsFileChange[])
---  :get_file_diff_raw(path)   (returns raw diff string or nil)
---  :get_file_at_base(path)    (returns the file's lines at the base revision)
---
---@param BackendClass table The backend class table (e.g. GitBackend or JjBackend)
---@return table Class A new class table augmented with shared methods
function M.create_backend(BackendClass)
	-- Create a new class that delegates to BackendClass for backend-specific methods
	local Class = setmetatable({}, { __index = BackendClass })
	Class.__index = Class

	-- Private per-backend singleton cache
	local instances = {}

	---Create a new backend instance with the correct metatable
	---@param dir string Directory
	---@return VcsBackend|nil backend Backend instance or nil
	function Class.new(dir)
		local backend = BackendClass.new(dir)
		if backend then
			setmetatable(backend, Class)
		end
		return backend
	end

	---Get or create backend instance for a directory
	---@param dir? string Directory (defaults to cwd)
	---@return VcsBackend|nil backend Backend instance or nil if not a valid repo
	function Class.instance(dir)
		dir = dir or vim.fn.getcwd()

		-- Resolve to absolute path. fnamemodify is typed as possibly-nil in the
		-- bundled vim stubs, so pin it to string for the gsub below.
		dir = vim.fn.fnamemodify(dir, ":p") --[[@as string]]
		dir = dir:gsub("/$", "") -- Remove trailing slash

		if instances[dir] then
			return instances[dir]
		end

		local backend = Class.new(dir)
		if backend then
			instances[dir] = backend
		end
		return backend
	end

	---Get the repository root directory
	---@return string root Repository root
	function Class:get_root()
		return self.root
	end

	---Get the current reference (commit SHA or change ID)
	---@return string ref Current reference
	function Class:get_ref()
		return self.ref
	end

	---Get the current branch/bookmark name
	---@return string|nil branch Branch name or nil if detached
	function Class:get_branch()
		return self.branch
	end

	---Check if there are uncommitted changes
	---@return boolean has_changes True if there are changes
	function Class:has_changes()
		local files = self:get_changed_files()
		return #files > 0
	end

	---Read a file from the repository working copy
	---@param file_path string File path relative to repo root
	---@return string[]|nil lines File lines or nil on error
	function Class:read_file(file_path)
		local full_path = self.root .. "/" .. file_path
		local ok, lines = pcall(vim.fn.readfile, full_path)
		if not ok then
			return nil
		end
		return lines
	end

	---Clear cached backend instance
	---@param dir? string Directory to clear (clears all if nil)
	function Class.clear_cache(dir)
		if dir then
			instances[dir] = nil
		else
			instances = {}
		end
	end

	-- Backwards compatibility alias
	Class.get_head = Class.get_ref

	return Class
end

return M
