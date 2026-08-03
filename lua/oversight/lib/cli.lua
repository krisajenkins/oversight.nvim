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
---@field timeout_ms number Milliseconds before giving up; inherited from the
---class default unless `timeout()` sets it on the instance.
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

---The structured result every invocation resolves to. `call()` always hands
---back one of these, never nil; on the infrastructure-failure paths (binary
---missing, spawn error, timeout) `exit_code` is -1 and `stderr` carries the
---explanation.
---@class CliResult
---@field success boolean Whether command succeeded
---@field exit_code number Exit code, or -1 for an infrastructure failure
---@field stdout string Standard output
---@field stderr string Standard error, or the failure message

---How long to wait for a command before giving up, in milliseconds.
---
---plenary's Job:sync defaults to 5s, which is too tight for `git diff` on a
---large repo or for jj's first-run working-copy snapshot — and the failure was
---invisible, because the timeout arrived as a raised error that we turned into
---an empty-looking result with no notification. A slow diff therefore rendered
---as "no changes".
---
---Overridable per builder with `:timeout(ms)`; assign here to change the
---default for everything.
Cli.timeout_ms = 60000

---Override the timeout for this command only.
---@param ms number Milliseconds to wait before giving up
---@return CliBuilder self For chaining
function Cli:timeout(ms)
	self.timeout_ms = ms
	return self
end

---Resolve a command to an absolute path, failing loudly when it isn't on PATH.
---Without this the bare name reaches Job:new, which raises
---"<cmd>: Executable not found" with a traceback that we would surface to the
---caller as `stderr`.
---@param cmd string Command name (e.g. "git", "jj")
---@return string? command Resolved absolute path, or nil when not found
---@return CliResult? failure Failure result when not found
local function resolve_command(cmd)
	local resolved = vim.fn.exepath(cmd)
	if resolved == "" then
		local msg = cmd .. " executable not found on PATH"
		-- logger.error already routes to vim.notify at ERROR level, so this is
		-- both logged and surfaced — don't add a second vim.notify here.
		logger.error("%s", msg)
		return nil, {
			success = false,
			exit_code = -1,
			stdout = "",
			stderr = msg,
		}
	end
	return resolved
end

---Build the structured result from a finished job.
---@param job table The plenary Job
---@param stdout string[]|string|nil Captured stdout, as returned by job:sync()
---@return CliResult result
local function build_result(job, stdout)
	local exit_code = job.code
	stdout = stdout or job:result() or {}
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

---Execute the command synchronously
---@return CliResult result Command result
function Cli:call()
	local cmd_args = vim.deepcopy(self.args)
	local cwd = self.options.cwd or vim.fn.getcwd()

	local command, failure = resolve_command(self.cmd)
	if not command then
		return failure
	end

	logger.debug("Executing: %s %s (cwd: %s)", command, table.concat(cmd_args, " "), cwd)

	-- Guard both Job:new (which raises when the executable is missing) and
	-- job:sync (which raises on timeout) so an infrastructure failure becomes a
	-- normal failure table rather than a stack trace at the caller.
	local ok, result = pcall(function()
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
		-- plenary's Job:sync(timeout, wait_interval) accepts a timeout; its
		-- bundled type stub omits the params, so silence the false positive.
		---@diagnostic disable-next-line: redundant-parameter
		local stdout = job:sync(self.timeout_ms)
		return { job = job, stdout = stdout }
	end)

	if not ok then
		local err = tostring(result)
		-- Both logger paths notify the user (see logger.lua), so phrase these
		-- for a human: the old code passed plenary's raw error through, which
		-- meant a timeout surfaced as a stack trace. plenary words a timeout as
		-- "'<cmd> <args>' was unable to complete in <n> ms".
		if err:match("unable to complete") then
			logger.warn("%s timed out after %dms", self.cmd, self.timeout_ms)
		else
			logger.error("failed to run %s: %s", self.cmd, err)
		end
		return {
			success = false,
			exit_code = -1,
			stdout = "",
			stderr = err,
		}
	end

	return build_result(result.job, result.stdout)
end

-- 0.9 spells the libuv binding `vim.loop`; `vim.uv` arrived in 0.10.
local uv = vim.uv or vim.loop

---Execute the command without blocking, from within a plenary async context.
---
---Yields the calling coroutine until the process exits or the timeout fires, so
---Neovim stays responsive throughout — unlike `call()`, which blocks the whole
---editor for as long as the command takes.
---
---Must be called from inside a coroutine (`async.run`, `async.void`, …). Outside
---one, plenary's wrapper raises.
---@return CliResult result Command result
function Cli:call_async()
	local async = require("plenary.async")

	return async.wrap(function(callback)
		local cmd_args = vim.deepcopy(self.args)
		local cwd = self.options.cwd or vim.fn.getcwd()

		local command, failure = resolve_command(self.cmd)
		if not command then
			return callback(failure)
		end

		logger.debug("Executing async: %s %s (cwd: %s)", command, table.concat(cmd_args, " "), cwd)

		-- The exit callback and the timeout timer race each other, and resuming
		-- an already-resumed coroutine raises. Everything that finishes the call
		-- goes through here so exactly one of them wins.
		local finished = false
		local timer = uv.new_timer()

		local function finish(result)
			if finished then
				return
			end
			finished = true
			if timer and not timer:is_closing() then
				timer:stop()
				timer:close()
			end
			callback(result)
		end

		local job = Job:new({
			command = command,
			args = cmd_args,
			cwd = cwd,
			-- See call(): a non-nil env replaces the child's whole environment.
			env = next(self._env) and self._env or nil,
		})

		-- libuv callbacks run on the loop thread, where Neovim API calls are
		-- illegal; schedule_wrap hops back to the main loop before we touch
		-- anything (including the logger, which notifies).
		job:add_on_exit_callback(vim.schedule_wrap(function(finished_job)
			finish(build_result(finished_job, nil))
		end))

		if timer then
			timer:start(
				self.timeout_ms,
				0,
				vim.schedule_wrap(function()
					logger.warn("%s timed out after %dms", self.cmd, self.timeout_ms)
					-- Kill the process before resuming, or it outlives the call
					-- and its exit callback fires against a dead coroutine.
					pcall(function()
						job:shutdown(-1)
					end)
					finish({
						success = false,
						exit_code = -1,
						stdout = "",
						stderr = string.format("%s timed out after %dms", self.cmd, self.timeout_ms),
					})
				end)
			)
		end

		-- Job:start can still raise (bad cwd, fork failure), and that happens on
		-- this side of the callback, so it has to become a result too.
		local ok, err = pcall(function()
			job:start()
		end)
		if not ok then
			local message = tostring(err)
			logger.error("failed to run %s: %s", self.cmd, message)
			finish({ success = false, exit_code = -1, stdout = "", stderr = message })
		end
	end, 1)()
end

return Cli
