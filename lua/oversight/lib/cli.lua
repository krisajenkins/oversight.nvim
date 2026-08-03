-- CLI command builder
-- Fluent interface for constructing and executing shell commands

local Job = require("plenary.job")
local logger = require("oversight.logger")

---@class CliBuilder
---@field cmd string Command to execute
---@field args string[] Command arguments
---@field options table Command options
---@field _env table<string, string> Environment variables set via `env()`. Named
---with a leading underscore so it does not shadow the `env()` method on the
---metatable — an `env` instance field would make `builder:env(k, v)` raise
---"attempt to call method 'env' (a table value)".
local Cli = {}
Cli.__index = Cli

---Create a new CLI builder
---@param cmd string Command name (e.g. "git", "jj")
---@return CliBuilder builder CLI builder instance
function Cli.new(cmd)
	local builder = setmetatable({}, Cli)
	builder.cmd = cmd
	builder.args = {}
	builder.options = {}
	builder._env = {}
	return builder
end

---Add a positional argument
---@param value string Argument value
---@return CliBuilder self For chaining
function Cli:arg(value)
	table.insert(self.args, value)
	return self
end

---Add an option (--key value or --key)
---@param key string Option key
---@param value? string Option value (optional)
---@return CliBuilder self For chaining
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
---@return CliBuilder self For chaining
function Cli:flag(key)
	table.insert(self.args, "--" .. key)
	return self
end

---Add a short flag (-k)
---@param key string Flag key (single character)
---@return CliBuilder self For chaining
function Cli:short_flag(key)
	table.insert(self.args, "-" .. key)
	return self
end

---Set an environment variable
---@param key string Environment variable name
---@param value string Environment variable value
---@return CliBuilder self For chaining
function Cli:env(key, value)
	self._env[key] = value
	return self
end

---Set working directory
---@param dir string Working directory
---@return CliBuilder self For chaining
function Cli:cwd(dir)
	self.options.cwd = dir
	return self
end

---@class CliResult
---@field success boolean Whether command succeeded
---@field exit_code number Exit code
---@field stdout string Standard output
---@field stderr string Standard error

---Execute the command synchronously
---@return CliResult result Command result
function Cli:call()
	local cmd_args = vim.deepcopy(self.args)
	local cwd = self.options.cwd or vim.fn.getcwd()

	-- Resolve full path for command at call time
	local command = self.cmd
	local resolved = vim.fn.exepath(command)
	if resolved ~= "" then
		command = resolved
	end

	logger.debug("Executing: %s %s (cwd: %s)", command, table.concat(cmd_args, " "), cwd)

	local job = Job:new({
		command = command,
		args = cmd_args,
		cwd = cwd,
		-- Only pass env when the caller has actually set variables. plenary's Job
		-- treats any non-nil env table as the *entire* child environment, so an
		-- empty-but-non-nil table would strip HOME, PATH, SSH_AUTH_SOCK, GIT_*,
		-- JJ_CONFIG and the rest — leaving git and jj to run without the user's
		-- own config. Passing nil lets the child inherit ours.
		env = next(self._env) and self._env or nil,
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
---@return CliResult result Command result
function Cli:call_async()
	local async = require("plenary.async")
	return async.wrap(function(callback)
		local result = self:call()
		callback(result)
	end, 1)()
end

return Cli
