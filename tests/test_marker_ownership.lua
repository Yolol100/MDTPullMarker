local clock = 100.0
local sent = {}
local instructionChanges = {}

local Addon = {
  Version = "test-rc52",
  DungeonSession = {
    GetState = function()
      return { active = true, routeMatches = true }
    end,
  },
  RuntimeController = {
    GetState = function()
      return { planStatus = "ready", pullCount = 1 }
    end,
  },
  MarkerExecutor = {
    OnInstructionChanged = function(_self, reason)
      instructionChanges[#instructionChanges + 1] = reason
      return true
    end,
  },
}

function Addon.IsSecret(_value)
  return false
end

function GetTimePreciseSec()
  return clock
end

function GetNormalizedRealmName()
  return "Realm"
end

function UnitFullName(unit)
  if unit == "player" then return "Player", "Realm" end
  if unit == "party1" then return "Tank", "Realm" end
  return nil, nil
end

function UnitIsDeadOrGhost(_unit)
  return false
end

function IsInGroup()
  return true
end

function GetNumGroupMembers()
  return 2
end

function IsInRaid()
  return false
end

function UnitIsGroupLeader(_unit)
  return false
end

function UnitGroupRolesAssigned(unit)
  if unit == "party1" then return "TANK" end
  return "DAMAGER"
end

C_ChatInfo = {
  IsAddonMessagePrefixRegistered = function(_prefix)
    return true
  end,
  RegisterAddonMessagePrefix = function(_prefix)
    return true
  end,
  SendAddonMessage = function(prefix, payload, channel)
    sent[#sent + 1] = { prefix = prefix, payload = payload, channel = channel }
    return true
  end,
}

C_Timer = {
  After = function(_delay, _callback)
    -- Timer scheduling is intentionally inert in this deterministic harness.
    -- Tests advance the fake clock and invoke public lifecycle methods directly.
  end,
}

local chunk = assert(loadfile("Runtime/MarkerOwnership.lua"))
chunk("MDTPullMarker", Addon)
assert(Addon.MarkerOwnership, "MarkerOwnership was not loaded")

local ownership = Addon.MarkerOwnership
assert(ownership:Initialize() == true, "ownership initialization failed")

-- A peer without the explicit protocol and below the rc52 legacy boundary is
-- accepted as a transport message but must make election fail closed.
local accepted = ownership:OnAddonMessage(
  "MDTPM_OWNER",
  "H|1.0-rc51|1",
  "PARTY",
  "Tank-Realm"
)
assert(accepted == true, "valid legacy ownership message should be parsed")
local state = ownership:GetState()
assert(state.owner == nil, "incompatible peer must prevent owner election")
assert(state.ownerReason == "owner-protocol-incompatible-peer", "incompatible peer must fail closed")
assert(state.incompatiblePeerCount == 1, "incompatible peer must be counted")

-- The same peer becomes eligible once it explicitly advertises protocol v1.
accepted = ownership:OnAddonMessage(
  "MDTPM_OWNER",
  "H|1.0|1|1",
  "PARTY",
  "Tank-Realm"
)
assert(accepted == true, "explicit owner protocol should be accepted")
state = ownership:GetState()
assert(state.owner == "Tank-Realm", "eligible tank must outrank local DPS")
assert(state.incompatiblePeerCount == 0, "compatible peer must leave incompatible count")
assert(state.ownerProtocolVersion == 1, "local owner protocol must remain version 1")

-- Let the initial settle window expire, then freeze the settled tank owner.
clock = 101.0
local combatOwner = ownership:OnCombatStarted()
assert(combatOwner == "Tank-Realm", "combat must snapshot the settled owner")
state = ownership:GetState()
assert(state.combatFrozen == true, "combat must freeze ownership")

-- A live eligibility update during combat may change the underlying election,
-- but effective ownership must remain frozen until combat ends.
accepted = ownership:OnAddonMessage(
  "MDTPM_OWNER",
  "H|1.0|0|1",
  "PARTY",
  "Tank-Realm"
)
assert(accepted == true, "peer eligibility update should be accepted")
state = ownership:GetState()
assert(state.owner == "Tank-Realm", "effective owner must remain frozen during combat")
assert(state.combatFrozen == true, "combat freeze must survive peer updates")

ownership:OnCombatEnded()
state = ownership:GetState()
assert(state.combatFrozen == false, "combat end must release owner freeze")
assert(state.owner == "Player-Realm", "post-combat election must use current eligibility")

assert(#sent > 0, "ownership initialization should exercise addon-message transport")
assert(#instructionChanges > 0, "ownership lifecycle should notify execution layer")

print("ok - ownership protocol election and combat freeze behavior")
