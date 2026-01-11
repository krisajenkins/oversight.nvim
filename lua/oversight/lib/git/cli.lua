local Job = require("plenary.job")
local logger = require("oversight.logger")

---@class GitCli
---@field cmd string Command to execute
---@field args string[] Command arguments
---@field options table Command options
---@field env table Environment variables
local Cli = {}
Cli.__index = Cli

---Create a new CLI builder
---@param cmd? string Command (defaults to "git")
---@return GitCli builder CLI builder instance
local function new_builder(cmd)
	local builder = setmetatable({}, Cli)
	builder.cmd = cmd or "git"
	builder.args = {}
	builder.options = {}
	builder.env = {}
	return builder
end

---Add a positional argument
---@param value string Argument value
---@return GitCli self For chaining
function Cli:arg(value)
	table.insert(self.args, value)
	return self
end

---Add multiple positional arguments
---@param values string[] Argument values
---@return GitCli self For chaining
function Cli:args(values)
	vim.list_extend(self.args, values)
	return self
end

---Add an option (--key value or --key)
---@param key string Option key
---@param value? string Option value (optional)
---@return GitCli self For chaining
function Cli:option(key, value)
	if value then
		table.insert(self.args, "--" .. key)
		table.insert(self.args, value)
	else
		table.insert(self.args, "--" .. key)
	end
	return self
end

---Add a flag (--key)
---@param key string Flag key
---@return GitCli self For chaining
function Cli:flag(key)
	table.insert(self.args, "--" .. key)
	return self
end

---Add a short flag (-k)
---@param key string Flag key (single character)
---@return GitCli self For chaining
function Cli:short_flag(key)
	table.insert(self.args, "-" .. key)
	return self
end

---Set an environment variable
---@param key string Environment variable name
---@param value string Environment variable value
---@return GitCli self For chaining
function Cli:env(key, value)
	self.env[key] = value
	return self
end

---Set working directory
---@param dir string Working directory
---@return GitCli self For chaining
function Cli:cwd(dir)
	self.options.cwd = dir
	return self
end

---@class GitResult
---@field success boolean Whether command succeeded
---@field exit_code number Exit code
---@field stdout string Standard output
---@field stderr string Standard error

---Execute the command synchronously
---@return GitResult result Command result
function Cli:call()
	local cmd_args = vim.deepcopy(self.args)
	local cwd = self.options.cwd or vim.fn.getcwd()

	-- Resolve full path for git command at call time
	local command = self.cmd
	if command == "git" then
		local git_path = vim.fn.exepath("git")
		if git_path ~= "" then
			command = git_path
		end
	end

	logger.debug("Executing: %s %s (cwd: %s)", command, table.concat(cmd_args, " "), cwd)

	local job = Job:new({
		command = command,
		args = cmd_args,
		cwd = cwd,
		env = self.env,
	})

	local ok, result = pcall(function()
		return job:sync()
	end)

	if not ok then
		logger.error("Command failed: %s", tostring(result))
		return {
			success = false,
			exit_code = -1,
			stdout = "",
			stderr = tostring(result),
		}
	end

	local exit_code = job.code
	local stdout = result or {}
	local stderr = job:stderr_result() or {}

	local success = exit_code == 0
	local stdout_str = type(stdout) == "table" and table.concat(stdout, "\n") or stdout
	local stderr_str = type(stderr) == "table" and table.concat(stderr, "\n") or stderr

	if not success then
		local error_msg = "Command failed with exit code " .. exit_code
		if stderr_str and stderr_str ~= "" then
			error_msg = error_msg .. ": " .. stderr_str
		end
		logger.debug("%s", error_msg)
	end

	return {
		success = success,
		exit_code = exit_code,
		stdout = stdout_str,
		stderr = stderr_str,
	}
end

---Execute the command asynchronously
---@return GitResult result Command result
function Cli:call_async()
	local async = require("plenary.async")
	return async.wrap(function(callback)
		local result = self:call()
		callback(result)
	end, 1)()
end

-- Module with convenience constructors
local M = {}

---Create a git diff builder
---@return GitCli builder CLI builder
function M.diff()
	return new_builder("git"):arg("diff"):flag("no-color")
end

---Create a git status builder
---@return GitCli builder CLI builder
function M.status()
	return new_builder("git"):arg("status")
end

---Create a git show builder
---@return GitCli builder CLI builder
function M.show()
	return new_builder("git"):arg("show"):flag("no-color")
end

---Create a git log builder
---@return GitCli builder CLI builder
function M.log()
	return new_builder("git"):arg("log")
end

---Create a git rev-parse builder
---@return GitCli builder CLI builder
function M.rev_parse()
	return new_builder("git"):arg("rev-parse")
end

---Create a git branch builder
---@return GitCli builder CLI builder
function M.branch()
	return new_builder("git"):arg("branch")
end

---Create a raw git builder
---@return GitCli builder CLI builder
function M.raw()
	return new_builder("git")
end

return M
