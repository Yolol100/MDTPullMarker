local file = assert(io.open("Runtime/MarkerOwnership.lua", "rb"))
local source = file:read("*a")
file:close()

assert(type(source) == "string" and #source > 0, "ownership source is missing")
local _, compatibilityCalls = source:gsub("peerOwnerProtocolCompatible", "")
assert(compatibilityCalls >= 2, "owner protocol compatibility guard is missing")
local _, localKeyUses = source:gsub("localKey", "")
assert(localKeyUses >= 2, "local participant filter is missing")

print("ok - ownership compatibility guard")
