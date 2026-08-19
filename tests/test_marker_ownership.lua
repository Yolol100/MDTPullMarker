local clock = 100.0
local sent = {}
local instructionChanges = {}
local challengeMapID = nil
local tankPresent = true
local chatLockdown = false
local SECRET = {}

local Addon = {
  Version = "test-rc60",
  DungeonSession = {
    GetState = function()
      return {
        active = true,
        routeMatches = true,
        isMythicPlus = challengeMapID ~= nil,
        challengeCompleted = false,
      }
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

function Addon.IsSecret(value)
  return value == SECRET
end

function GetTimePreciseSec()
  return clock
end

function GetNormalizedRealmName()
  return "Realm"
end

function UnitFullName(unit)
  if unit == "player" then return "Player", "Realm" end
  if unit == "party1" and tankPresent then return "Tank", "Realm" end
  return nil, nil
end

function UnitIsDeadOrGhost(_unit)
  return false
end

function IsInGroup()
  return tankPresent
end

function GetNumGroupMembers()
  return tankPresent and 2 or 1
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

C_ChallengeMode = {
  GetActiveChallengeMapID = function()
    return challengeMapID
  end,
}

C_ChatInfo = {
  InChatMessagingLockdown = function()
    return chatLockdown
  end,
  IsAddonMessagePrefixRegistered = function(_prefix)
    return true
  end,
  RegisterAddonMessagePrefix = function(_prefix)
    return true
  end,
  SendAddonMessage = function(prefix, payload, channel)
    if chatLockdown then error("SendAddonMessage blocked during Midnight challenge") end
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

-- Every externally supplied CHAT_MSG_ADDON field is a trust boundary. Malformed,
-- secret, overlong or wrongly scoped messages must be rejected without throwing
-- and without creating peer state.
local function assertRejected(prefix, message, channel, sender, label)
  local before = ownership:GetState().peerCount
  local ok, result = pcall(ownership.OnAddonMessage, ownership, prefix, message, channel, sender)
  assert(ok, label .. " must not throw")
  assert(result == false, label .. " must be rejected")
  assert(ownership:GetState().peerCount == before, label .. " must not create peer state")
end

assertRejected("OTHER", "H|1.0|1|1", "PARTY", "Tank-Realm", "wrong prefix")
assertRejected("MDTPM_OWNER", {}, "PARTY", "Tank-Realm", "non-string payload")
assertRejected("MDTPM_OWNER", SECRET, "PARTY", "Tank-Realm", "secret payload")
assertRejected("MDTPM_OWNER", string.rep("x", 121), "PARTY", "Tank-Realm", "overlong payload")
assertRejected("MDTPM_OWNER", "H|1.0|1|1", "SAY", "Tank-Realm", "wrong channel")
assertRejected("MDTPM_OWNER", "H|1.0|1|1", "PARTY", "Player-Realm", "self sender")
assertRejected("MDTPM_OWNER", "H|1.0|2|1", "PARTY", "Tank-Realm", "malformed eligibility")
assertRejected("MDTPM_OWNER", "H|1.0|1|0", "PARTY", "Tank-Realm", "protocol zero")
assertRejected("MDTPM_OWNER", "H|1.0|1|256", "PARTY", "Tank-Realm", "protocol overflow")

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

-- Once the keystone starts, freeze the settled owner for the full challenge.
-- Midnight suspends addon/chat messaging here, so no heartbeat or combat event
-- may attempt SendAddonMessage or discard the pre-key election.
clock = 101.0
local sendsBeforeChallenge = #sent
challengeMapID = 503
chatLockdown = true
ownership:RefreshEligibility("challenge-started")
state = ownership:GetState()
assert(state.challengeFrozen == true, "active challenge must freeze ownership")
assert(state.owner == "Tank-Realm", "challenge must preserve the settled tank owner")
assert(state.electionPending == false, "challenge freeze must suppress election state")
assert(#sent == sendsBeforeChallenge, "challenge start must not send addon messages")

local combatOwner = ownership:OnCombatStarted()
assert(combatOwner == "Tank-Realm", "combat must use the challenge-frozen owner")
ownership:OnCombatEnded()
ownership:OnGroupChanged("GROUP_ROSTER_UPDATE")
state = ownership:GetState()
assert(state.owner == "Tank-Realm", "combat/group events must not re-elect during the challenge")
assert(#sent == sendsBeforeChallenge, "challenge lifecycle must remain message-free")

local isOwner, reason, owner = ownership:IsOwner()
assert(isOwner == false and reason == "marker-owner-passive", "non-owner must remain passive during challenge")
assert(owner == "Tank-Realm", "passive result must expose the frozen owner")

-- If the frozen owner positively leaves the roster, fail closed. Do not elect a
-- replacement while addon communication is unavailable, because two clients
-- could otherwise independently take ownership.
tankPresent = false
ownership:OnGroupChanged("GROUP_ROSTER_UPDATE")
state = ownership:GetState()
assert(state.owner == nil, "owner departure during challenge must fail closed")
assert(state.ownerReason == "challenge-owner-left", "owner departure must be diagnosed")
assert(#sent == sendsBeforeChallenge, "owner departure must not trigger in-key election traffic")

-- After the challenge ends, normal election/communication semantics resume.
challengeMapID = nil
chatLockdown = false
ownership:OnWorldChanged("challenge-ended")
state = ownership:GetState()
assert(state.challengeFrozen == false, "challenge end must release challenge freeze")
assert(state.owner == "Player-Realm", "solo post-challenge state should elect the local player")

-- Starting a key while the short ownership settle window is still open must
-- fail closed for that challenge. Even if a provisional deterministic winner is
-- visible locally, peers may not have converged yet; freezing it could create a
-- split-brain owner after Midnight locks addon communications.
tankPresent = true
clock = 200.0
ownership:OnGroupChanged("pre-key-roster-refresh")
accepted = ownership:OnAddonMessage(
  "MDTPM_OWNER",
  "H|1.0|1|1",
  "PARTY",
  "Tank-Realm"
)
assert(accepted == true, "compatible peer should be accepted during settle")
state = ownership:GetState()
assert(state.electionPending == true, "pre-key refresh must still be settling")
assert(state.owner == "Tank-Realm", "provisional owner should be visible before challenge freeze")

local sendsBeforeUnsettledChallenge = #sent
clock = 200.2
challengeMapID = 504
chatLockdown = true
ownership:RefreshEligibility("challenge-started-during-settle")
state = ownership:GetState()
assert(state.challengeFrozen == true, "challenge must freeze even when election is unsettled")
assert(state.owner == nil, "unsettled challenge start must not freeze a provisional owner")
assert(state.ownerReason == "challenge-election-unsettled", "unsettled challenge start must be diagnosed")
assert(state.electionPending == false, "challenge freeze must suppress pending election state")
assert(#sent == sendsBeforeUnsettledChallenge, "unsettled challenge start must not send during lockdown")

isOwner, reason, owner = ownership:IsOwner()
assert(isOwner == false and reason == "marker-owner-unavailable" and owner == nil,
  "unsettled challenge must remain passive instead of risking split-brain")

challengeMapID = nil
chatLockdown = false
ownership:OnWorldChanged("unsettled-challenge-ended")
state = ownership:GetState()
assert(state.challengeFrozen == false, "challenge end must release unsettled freeze")

assert(#sent > 0, "pre-challenge ownership initialization should exercise addon-message transport")
assert(#instructionChanges > 0, "ownership lifecycle should notify execution layer")

print("ok - ownership protocol malformed-input matrix, election, Midnight challenge freeze and unsettled-start fail-closed behavior")
