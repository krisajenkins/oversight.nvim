-- Simple logging utility for tuicr

local M = {}

---@alias LogLevel "debug"|"info"|"warn"|"error"

---@type LogLevel
M.level = "info"

local levels = {
	debug = 1,
	info = 2,
	warn = 3,
	error = 4,
}

---@param level LogLevel
---@param msg string
---@param ... any
local function log(level, msg, ...)
	if levels[level] < levels[M.level] then
		return
	end

	local formatted = string.format(msg, ...)
	local prefix = string.format("[tuicr:%s]", level)

	if level == "error" then
		vim.notify(prefix .. " " .. formatted, vim.log.levels.ERROR)
	elseif level == "warn" then
		vim.notify(prefix .. " " .. formatted, vim.log.levels.WARN)
	elseif level == "info" then
		vim.notify(prefix .. " " .. formatted, vim.log.levels.INFO)
	else
		vim.notify(prefix .. " " .. formatted, vim.log.levels.DEBUG)
	end
end

---@param msg string
---@param ... any
function M.debug(msg, ...)
	log("debug", msg, ...)
end

---@param msg string
---@param ... any
function M.info(msg, ...)
	log("info", msg, ...)
end

---@param msg string
---@param ... any
function M.warn(msg, ...)
	log("warn", msg, ...)
end

---@param msg string
---@param ... any
function M.error(msg, ...)
	log("error", msg, ...)
end

return M
