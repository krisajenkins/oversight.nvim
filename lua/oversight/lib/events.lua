-- Minimal event emitter for decoupled component communication

---@class EventEmitter
---@field private _listeners table<string, function[]>
---@field private _once table<string, table<function, boolean>>
local EventEmitter = {}
EventEmitter.__index = EventEmitter

---Create a new EventEmitter
---@return EventEmitter
function EventEmitter.new()
	return setmetatable({
		_listeners = {},
		_once = {},
	}, EventEmitter)
end

---Register an event listener
---@param event string Event name
---@param listener function Callback function
---@return function unsubscribe Function to remove the listener
function EventEmitter:on(event, listener)
	if not self._listeners[event] then
		self._listeners[event] = {}
	end
	table.insert(self._listeners[event], listener)

	-- Return unsubscribe function
	return function()
		self:off(event, listener)
	end
end

---Register a one-time event listener
---@param event string Event name
---@param listener function Callback function
---@return function unsubscribe Function to remove the listener
function EventEmitter:once(event, listener)
	if not self._once[event] then
		self._once[event] = {}
	end
	self._once[event][listener] = true
	return self:on(event, listener)
end

---Remove a specific listener
---@param event string Event name
---@param listener function Listener to remove
function EventEmitter:off(event, listener)
	local listeners = self._listeners[event]
	if not listeners then
		return
	end

	for i, l in ipairs(listeners) do
		if l == listener then
			table.remove(listeners, i)
			break
		end
	end

	-- Clean up once tracking
	if self._once[event] then
		self._once[event][listener] = nil
	end
end

---Emit an event to all listeners
---@param event string Event name
---@param ... any Arguments to pass to listeners
---@return boolean had_listeners True if any listeners were called
function EventEmitter:emit(event, ...)
	local listeners = self._listeners[event]
	if not listeners or #listeners == 0 then
		return false
	end

	-- Copy listener list to allow modification during iteration
	local to_call = {}
	for _, listener in ipairs(listeners) do
		table.insert(to_call, listener)
	end

	-- Call all listeners
	for _, listener in ipairs(to_call) do
		listener(...)

		-- Remove once listeners after calling
		if self._once[event] and self._once[event][listener] then
			self:off(event, listener)
		end
	end

	return true
end

---Remove all listeners
---@param event? string Optional event name; if nil, clears all events
function EventEmitter:clear(event)
	if event then
		self._listeners[event] = nil
		self._once[event] = nil
	else
		self._listeners = {}
		self._once = {}
	end
end

---Get the number of listeners for an event
---@param event string Event name
---@return number count
function EventEmitter:listener_count(event)
	local listeners = self._listeners[event]
	return listeners and #listeners or 0
end

return EventEmitter
