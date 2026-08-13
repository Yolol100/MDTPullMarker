local file = assert(io.open("Runtime/MarkerOwnership.lua", "rb"))
local source = file:read("*a")
file:close()

assert(type(source) == "string" and #source > 0, "ownership source is missing")
assert(source:find("peerOwnerProtocolCompatible(peer)", 1, true), "owner protocol compatibility gate is missing")
assert(source:find("peer and peer.eligible == true and peerOwnerProtocolCompatible(peer)", 1, true), "only announced compatible peers may join election")
assert(source:find("key == localKey and state.localEligible == true", 1, true), "local eligibility gate is missing")
assert(source:find('state.ownerReason = "owner-protocol-incompatible-peer"', 1, true), "incompatible peers must fail closed")
assert(source:find("if state.combatFrozen then return state.combatOwner end", 1, true), "combat owner freeze is missing")
assert(source:find("state.combatOwner = state.owner", 1, true), "combat must snapshot the settled owner")

print("ok - ownership compatibility and combat-freeze guards")
