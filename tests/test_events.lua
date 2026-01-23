-- Tests for EventEmitter

local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

T["EventEmitter"] = MiniTest.new_set()

T["EventEmitter"]["creates new instance"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()
	expect.equality(type(emitter), "table")
	expect.equality(emitter:listener_count("test"), 0)
end

T["EventEmitter"]["on() registers listener"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local called = false
	emitter:on("test", function()
		called = true
	end)

	expect.equality(emitter:listener_count("test"), 1)
	emitter:emit("test")
	expect.equality(called, true)
end

T["EventEmitter"]["on() returns unsubscribe function"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local call_count = 0
	local unsubscribe = emitter:on("test", function()
		call_count = call_count + 1
	end)

	emitter:emit("test")
	expect.equality(call_count, 1)

	unsubscribe()
	emitter:emit("test")
	expect.equality(call_count, 1) -- Still 1, not called again
end

T["EventEmitter"]["emit() passes arguments to listeners"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local received_a, received_b, received_c = nil, nil, nil
	emitter:on("test", function(a, b, c)
		received_a, received_b, received_c = a, b, c
	end)

	emitter:emit("test", "hello", 42, { key = "value" })

	expect.equality(received_a, "hello")
	expect.equality(received_b, 42)
	expect.equality(type(received_c), "table")
	expect.equality(received_c["key"], "value")
end

T["EventEmitter"]["emit() returns true when listeners exist"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	emitter:on("test", function() end)
	local result = emitter:emit("test")

	expect.equality(result, true)
end

T["EventEmitter"]["emit() returns false when no listeners"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local result = emitter:emit("nonexistent")

	expect.equality(result, false)
end

T["EventEmitter"]["emit() calls multiple listeners in order"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local order = {}
	emitter:on("test", function()
		table.insert(order, 1)
	end)
	emitter:on("test", function()
		table.insert(order, 2)
	end)
	emitter:on("test", function()
		table.insert(order, 3)
	end)

	emitter:emit("test")

	expect.equality(order[1], 1)
	expect.equality(order[2], 2)
	expect.equality(order[3], 3)
end

T["EventEmitter"]["once() listener called only once"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local call_count = 0
	emitter:once("test", function()
		call_count = call_count + 1
	end)

	emitter:emit("test")
	emitter:emit("test")
	emitter:emit("test")

	expect.equality(call_count, 1)
end

T["EventEmitter"]["once() removes listener after call"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	emitter:once("test", function() end)
	expect.equality(emitter:listener_count("test"), 1)

	emitter:emit("test")
	expect.equality(emitter:listener_count("test"), 0)
end

T["EventEmitter"]["off() removes specific listener"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local call_count_a, call_count_b = 0, 0
	local listener_a = function()
		call_count_a = call_count_a + 1
	end
	local listener_b = function()
		call_count_b = call_count_b + 1
	end

	emitter:on("test", listener_a)
	emitter:on("test", listener_b)

	emitter:emit("test")
	expect.equality(call_count_a, 1)
	expect.equality(call_count_b, 1)

	emitter:off("test", listener_a)

	emitter:emit("test")
	expect.equality(call_count_a, 1) -- Not called again
	expect.equality(call_count_b, 2) -- Called again
end

T["EventEmitter"]["clear() removes all listeners for event"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	emitter:on("test", function() end)
	emitter:on("test", function() end)
	emitter:on("other", function() end)

	expect.equality(emitter:listener_count("test"), 2)
	expect.equality(emitter:listener_count("other"), 1)

	emitter:clear("test")

	expect.equality(emitter:listener_count("test"), 0)
	expect.equality(emitter:listener_count("other"), 1)
end

T["EventEmitter"]["clear() with no args removes all listeners"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	emitter:on("test", function() end)
	emitter:on("other", function() end)
	emitter:on("another", function() end)

	emitter:clear()

	expect.equality(emitter:listener_count("test"), 0)
	expect.equality(emitter:listener_count("other"), 0)
	expect.equality(emitter:listener_count("another"), 0)
end

T["EventEmitter"]["listener_count() returns correct count"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	expect.equality(emitter:listener_count("test"), 0)

	emitter:on("test", function() end)
	expect.equality(emitter:listener_count("test"), 1)

	emitter:on("test", function() end)
	expect.equality(emitter:listener_count("test"), 2)
end

T["EventEmitter"]["separate events are independent"] = function()
	local EventEmitter = require("oversight.lib.events")
	local emitter = EventEmitter.new()

	local event_a_count, event_b_count = 0, 0
	emitter:on("event_a", function()
		event_a_count = event_a_count + 1
	end)
	emitter:on("event_b", function()
		event_b_count = event_b_count + 1
	end)

	emitter:emit("event_a")
	expect.equality(event_a_count, 1)
	expect.equality(event_b_count, 0)

	emitter:emit("event_b")
	expect.equality(event_a_count, 1)
	expect.equality(event_b_count, 1)
end

return T
