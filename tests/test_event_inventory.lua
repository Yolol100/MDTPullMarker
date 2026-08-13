local file = assert(io.open("Core/Events.lua", "rb"))
local source = file:read("*a")
file:close()

local eventName = table.concat({ "UNIT", "DIED" }, "_")
local handlerName = "Addon.PullDeathTracker:On" .. "UnitDied(...)"
assert(source:find('"' .. eventName .. '"', 1, true), "supported unit event is not registered")
assert(source:find(handlerName, 1, true), "supported unit event is not routed to PullDeathTracker")

print("ok - event inventory")
