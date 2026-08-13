local _, Addon = ...

local Ownership = {}
Addon.MarkerOwnership = Ownership

local PREFIX = "MDTPM_OWNER"
local PEER_TTL_SECONDS = 18
local HEARTBEAT_SECONDS = 5
local SETTLE_SECONDS = 0.8
local MIN_COMPATIBLE_OWNER_PROTOCOL_RC = 52

local state = {
  initialized = false,
  commAvailable = false,
  commFailureReason = nil,
  localName = nil,
  localEligible = false,
  owner = nil,
  ownerReason = "uninitialized",
  peers = {},
  settlingUntil = 0,
  combatOwner = nil,
  combatFrozen = false,
  serial = 0,
  heartbeatSerial = 0,
}

local function isSecret(value)
  return Addon.IsSecret and Addon.IsSecret(value) or false
end

local function effectiveOwner()
  if state.combatFrozen then return state.combatOwner end
  return state.owner
end

local function now()
  local api = type(GetTimePreciseSec) == "function" and GetTimePreciseSec or GetTime
  if type(api) ~= "function" then return 0 end
  local ok, value = pcall(api)
  if not ok or isSecret(value) then return 0 end
  return tonumber(value) or 0
end

local function safeString(value, maxLength)
  if isSecret(value) or type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  if value == "" or #value > (maxLength or 120) then return nil end
  return value
end

local function localRealm()
  if type(GetNormalizedRealmName) == "function" then
    local ok, value = pcall(GetNormalizedRealmName)
    value = ok and not isSecret(value) and safeString(value, 80) or nil
    if value then return value end
  end
  if type(GetRealmName) == "function" then
    local ok, value = pcall(GetRealmName)
    value = ok and not isSecret(value) and safeString(value, 80) or nil
    if value then return value:gsub("%s+", "") end
  end
end

local function normalizeFullName(name, realm)
  name = safeString(name, 80)
  realm = safeString(realm, 80)
  if realm then realm = realm:gsub("%s+", "") end
  if not name then return nil end
  if name:find("-", 1, true) then return name end
  realm = realm or localRealm()
  return realm and (name.."-"..realm) or name
end

local function fullNameForUnit(unit)
  if type(UnitFullName) ~= "function" then
    if unit == "player" and type(UnitName) == "function" then return normalizeFullName(UnitName(unit)) end
    return nil
  end
  local ok, name, realm = pcall(UnitFullName, unit)
  if not ok or isSecret(name) or isSecret(realm) then return nil end
  return normalizeFullName(name, realm)
end

local function canonical(name)
  name = safeString(name, 180)
  return name and name:lower() or nil
end

local function groupCount()
  if type(GetNumGroupMembers) ~= "function" then return nil end
  local ok, count = pcall(GetNumGroupMembers)
  if not ok or isSecret(count) then return nil end
  count = tonumber(count)
  if not count or count < 0 or count > 40 or count % 1 ~= 0 then return nil end
  return count
end

-- Tri-state: true/false when WoW proves the group state, nil when the client
-- cannot safely determine it. Unknown must never be treated as solo.
local function inGroup()
  if type(IsInGroup) == "function" then
    local ok, value = pcall(IsInGroup)
    if ok and not isSecret(value) and type(value) == "boolean" then return value end
  end
  local count = groupCount()
  if count == nil then return nil end
  return count > 1
end

local function raidStatus()
  if type(IsInRaid) ~= "function" then return nil end
  local ok, value = pcall(IsInRaid)
  if not ok or isSecret(value) or type(value) ~= "boolean" then return nil end
  return value
end

local function roster()
  local result = {}
  local function add(unit)
    local name = fullNameForUnit(unit)
    local key = canonical(name)
    if not key then return false, "group-roster-incomplete" end
    if type(UnitIsGroupLeader) ~= "function" then return false, "group-roster-unavailable" end
    local leaderOK, leader = pcall(UnitIsGroupLeader, unit)
    if not leaderOK or isSecret(leader) or type(leader) ~= "boolean" then
      return false, "group-roster-unavailable"
    end
    if type(UnitGroupRolesAssigned) ~= "function" then return false, "group-roster-unavailable" end
    local roleOK, role = pcall(UnitGroupRolesAssigned, unit)
    if not roleOK or isSecret(role) or type(role) ~= "string"
      or (role ~= "TANK" and role ~= "DAMAGER" and role ~= "HEALER" and role ~= "NONE")
    then
      return false, "group-roster-unavailable"
    end
    result[key] = { name = name, unit = unit, leader = leader, role = role }
    return true
  end

  local count = groupCount()
  local raid = raidStatus()
  if not count or count < 2 or raid == nil or (not raid and count > 5) then
    return nil, "group-roster-unavailable"
  end

  local added, addError = add("player")
  if not added then return nil, addError end
  if raid then
    for index = 1, count do
      added, addError = add("raid"..index)
      if not added then return nil, addError end
    end
  else
    for index = 1, count - 1 do
      added, addError = add("party"..index)
      if not added then return nil, addError end
    end
  end

  local observed = 0
  for _ in pairs(result) do observed = observed + 1 end
  if observed ~= count then return nil, "group-roster-incomplete" end
  return result
end

local function currentEligibility()
  local session = Addon.DungeonSession:GetState()
  local runtime = Addon.RuntimeController:GetState()
  if type(UnitIsDeadOrGhost) ~= "function" then return false end
  local aliveOK, deadOrGhost = pcall(UnitIsDeadOrGhost, "player")
  if not aliveOK or isSecret(deadOrGhost) or type(deadOrGhost) ~= "boolean" then return false end
  local alive = deadOrGhost == false
  return alive and session and session.active == true and session.routeMatches == true
    and runtime and runtime.planStatus ~= "blocked" and runtime.pullCount and runtime.pullCount > 0 or false
end

local function candidateRank(entry)
  if entry and entry.role == "TANK" then return 0 end
  if entry and entry.leader then return 1 end
  if entry and entry.role == "DAMAGER" then return 2 end
  if entry and entry.role == "HEALER" then return 3 end
  return 4
end

local function peerReleaseCandidate(peer)
  local version = peer and peer.version
  if type(version) ~= "string" then return nil end
  return tonumber(version:match("%-rc(%d+)$"))
end

local function peerUsesHeartbeat(peer)
  local rc = peerReleaseCandidate(peer)
  return rc and rc >= 41 or false
end

local function peerOwnerProtocolCompatible(peer)
  local rc = peerReleaseCandidate(peer)
  return rc and rc >= MIN_COMPATIBLE_OWNER_PROTOCOL_RC or false
end

local function incompatibleOwnerPeer()
  local oldestName
  for _, peer in pairs(state.peers) do
    if not peerOwnerProtocolCompatible(peer) then
      if not oldestName or canonical(peer.name) < canonical(oldestName) then oldestName = peer.name end
    end
  end
  return oldestName
end

local function prunePeers(rosterMap)
  local cutoff = now() - PEER_TTL_SECONDS
  for key, peer in pairs(state.peers) do
    if not rosterMap[key] or tonumber(peer.lastSeen or 0) < cutoff then state.peers[key] = nil end
  end
end

local function hasLegacyPeer()
  for _, peer in pairs(state.peers) do
    if not peerUsesHeartbeat(peer) then return true end
  end
  return false
end

local function recomputeOwner(reason)
  local resolvedLocalName = fullNameForUnit("player")
  if resolvedLocalName then state.localName = resolvedLocalName end
  state.localName = state.localName or "player"
  state.localEligible = currentEligibility()
  local grouped = inGroup()

  if grouped == false then
    state.owner = state.localEligible and state.localName or nil
    state.ownerReason = "solo"
    return state.owner
  end
  if grouped ~= true then
    state.owner = nil
    state.ownerReason = "group-state-unavailable"
    return nil
  end
  if not state.commAvailable then
    state.owner = nil
    state.ownerReason = state.commFailureReason or "comm-unavailable"
    return nil
  end

  local rosterMap, rosterError = roster()
  if not rosterMap then
    state.owner = nil
    state.ownerReason = rosterError or "group-roster-unavailable"
    return nil
  end
  prunePeers(rosterMap)
  local incompatiblePeerName = incompatibleOwnerPeer()
  if incompatiblePeerName then
    state.owner = nil
    state.ownerReason = "owner-protocol-incompatible-peer"
    return nil
  end

  local candidates = {}
  for _, entry in pairs(rosterMap) do candidates[#candidates + 1] = entry end

  table.sort(candidates, function(left, right)
    local lr, rr = candidateRank(left), candidateRank(right)
    if lr ~= rr then return lr < rr end
    return canonical(left.name) < canonical(right.name)
  end)
  state.owner = candidates[1] and candidates[1].name or nil
  state.ownerReason = reason or (state.owner and "elected" or "no-eligible-owner")
  return state.owner
end

local function distribution()
  if inGroup() ~= true then return nil end
  local raid = raidStatus()
  if raid == nil then return nil end
  return raid and "RAID" or "PARTY"
end

local function addonMessageCallSucceeded(result)
  if isSecret(result) then return false end
  return result == true or (type(result) == "number" and result == 0)
end

local function prefixRegistrationState()
  if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.IsAddonMessagePrefixRegistered) ~= "function" then return nil end
  local ok, registered = pcall(C_ChatInfo.IsAddonMessagePrefixRegistered, PREFIX)
  if not ok or isSecret(registered) or type(registered) ~= "boolean" then return nil end
  return registered
end

local function failCommunication(reason)
  state.commAvailable = false
  state.commFailureReason = reason or "comm-unavailable"
  state.owner = nil
  state.ownerReason = state.commFailureReason
  state.settlingUntil = 0
  return false
end

local function registerCommunication()
  if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.RegisterAddonMessagePrefix) ~= "function" then
    return failCommunication("comm-register-unavailable")
  end

  if prefixRegistrationState() == true then
    state.commAvailable = true
    state.commFailureReason = nil
    return true
  end

  local ok, registered = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  local registrationSucceeded = ok and addonMessageCallSucceeded(registered)
  if not registrationSucceeded and ok and type(registered) == "number" and registered == 1 then
    registrationSucceeded = prefixRegistrationState() == true
  end
  state.commAvailable = registrationSucceeded
  if not state.commAvailable then return failCommunication("comm-register-failed") end
  state.commFailureReason = nil
  return true
end

local function send(kind)
  if not state.commAvailable then return false end
  if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.SendAddonMessage) ~= "function" then
    return failCommunication("comm-send-unavailable")
  end
  local channel = distribution()
  if not channel then return failCommunication("comm-channel-unavailable") end
  state.localEligible = currentEligibility()
  local payload = table.concat({ tostring(kind or "H"), tostring(Addon.Version or "unknown"), state.localEligible and "1" or "0" }, "|")
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, channel)
  if not ok or not addonMessageCallSucceeded(result) then
    return failCommunication("comm-send-failed")
  end
  return true
end

local function refreshExecutor(reason)
  recomputeOwner(reason)
  if Addon.MarkerExecutor and type(Addon.MarkerExecutor.OnInstructionChanged) == "function" then
    Addon.MarkerExecutor:OnInstructionChanged("marker-owner:"..tostring(reason or "changed"))
  end
  if Addon.RuntimeFrame and Addon.RuntimeFrame.IsOpen and Addon.RuntimeFrame:IsOpen() then Addon.RuntimeFrame:Refresh() end
end

local function parkUnsettledExecution(reason)
  if state.combatFrozen then return false, "combat-owner-frozen" end
  if Addon.MarkerExecutor and type(Addon.MarkerExecutor.OnInstructionChanged) == "function" then
    return Addon.MarkerExecutor:OnInstructionChanged("marker-owner:"..tostring(reason or "election-unsettled"))
  end
  return false, "executor-unavailable"
end

local startSettle

local function scheduleHeartbeat()
  if not state.initialized or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false end
  state.heartbeatSerial = state.heartbeatSerial + 1
  local serial = state.heartbeatSerial

  local function tick()
    if not state.initialized or serial ~= state.heartbeatSerial then return end
    local previousOwner = effectiveOwner()
    local grouped = inGroup()
    if grouped == true and not state.commAvailable then
      if registerCommunication() then
        startSettle("heartbeat-comm-recovered")
      else
        recomputeOwner("heartbeat-comm-unavailable")
      end
    else
      recomputeOwner("heartbeat")
      if grouped == true and state.commAvailable then
        send(hasLegacyPeer() and "H" or "B")
      end
    end
    local currentOwner = effectiveOwner()
    if previousOwner ~= currentOwner and not state.combatFrozen and now() >= state.settlingUntil then
      refreshExecutor("heartbeat-owner-changed")
    end
    C_Timer.After(HEARTBEAT_SECONDS, tick)
  end

  C_Timer.After(HEARTBEAT_SECONDS, tick)
  return true
end

startSettle = function(reason)
  local grouped = inGroup()
  if grouped == true and not state.commAvailable then registerCommunication() end
  if grouped ~= true or not state.commAvailable then
    state.settlingUntil = 0
    if state.combatFrozen then
      recomputeOwner(reason or "settle-skipped")
    else
      refreshExecutor(reason or "settle-skipped")
    end
    return
  end
  state.serial = state.serial + 1
  local serial = state.serial
  state.settlingUntil = now() + SETTLE_SECONDS
  recomputeOwner(reason or "settling")
  if not state.combatFrozen then parkUnsettledExecution("election-start") end
  if not send("H") then
    if not state.combatFrozen then refreshExecutor("comm-send-failed") end
    return
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(SETTLE_SECONDS + 0.05, function()
      if serial ~= state.serial then return end
      state.settlingUntil = 0
      if not state.combatFrozen then refreshExecutor("election-settled") end
    end)
  end
end

function Ownership:Initialize()
  if state.initialized then return true end
  state.localName = fullNameForUnit("player") or "player"
  registerCommunication()
  state.initialized = true
  startSettle("initialize")
  scheduleHeartbeat()
  return true
end

function Ownership:RefreshEligibility(reason)
  local before = state.localEligible
  state.localEligible = currentEligibility()
  recomputeOwner(reason or "eligibility")
  if before ~= state.localEligible and not send("H") and not state.combatFrozen then
    refreshExecutor("eligibility-comm-failed")
  end
  return self:GetState()
end

function Ownership:OnGroupChanged(reason)
  state.peers = {}
  startSettle(reason or "group-changed")
  return self:GetState()
end

function Ownership:OnWorldChanged(reason)
  startSettle(reason or "world-changed")
  return self:GetState()
end

function Ownership:OnAddonMessage(prefix, message, channel, sender)
  if prefix ~= PREFIX then return false end
  channel = safeString(channel, 20)
  if channel ~= "PARTY" and channel ~= "RAID" then return false end
  sender = normalizeFullName(safeString(sender, 180))
  local senderKey = canonical(sender)
  if not senderKey or senderKey == canonical(state.localName) then return false end
  local kind, version, eligible = tostring(message or ""):match("^([^|]+)|([^|]*)|([01])$")
  if kind ~= "H" and kind ~= "R" and kind ~= "B" then return false end
  state.peers[senderKey] = {
    name = sender,
    version = safeString(version, 40),
    eligible = eligible == "1",
    lastSeen = now(),
    channel = channel,
  }
  local previousOwner = effectiveOwner()
  recomputeOwner("peer-update")
  if kind == "H" then send("R") end
  local currentOwner = effectiveOwner()
  if previousOwner ~= currentOwner and not state.combatFrozen and now() >= state.settlingUntil then
    refreshExecutor("peer-owner-changed")
  end
  return true
end

function Ownership:OnCombatStarted()
  recomputeOwner("combat-start")
  state.combatFrozen = true
  if inGroup() == true and state.commAvailable and now() < state.settlingUntil then
    state.combatOwner = nil
    state.ownerReason = "combat-election-unsettled"
  else
    state.combatOwner = state.owner
  end
  return state.combatOwner
end

function Ownership:OnCombatEnded()
  state.combatOwner = nil
  state.combatFrozen = false
  startSettle("combat-ended")
  return self:GetState()
end

function Ownership:IsOwner()
  if not state.initialized then self:Initialize() end
  state.localEligible = currentEligibility()
  recomputeOwner("query")
  local owner = effectiveOwner()
  if not state.localEligible then return false, "marker-owner-ineligible", owner end
  if state.combatFrozen and not owner then return false, "marker-owner-unavailable", nil end
  if not owner and (state.ownerReason == "group-state-unavailable"
    or state.ownerReason == "group-roster-unavailable"
    or state.ownerReason == "group-roster-incomplete"
    or state.ownerReason == "comm-unavailable"
    or state.ownerReason == "comm-register-unavailable"
    or state.ownerReason == "comm-register-failed"
    or state.ownerReason == "comm-send-unavailable"
    or state.ownerReason == "comm-channel-unavailable"
    or state.ownerReason == "comm-send-failed"
    or state.ownerReason == "owner-protocol-incompatible-peer")
  then
    return false, "marker-owner-unavailable", nil
  end
  if inGroup() == true and state.commAvailable and not state.combatFrozen and now() < state.settlingUntil then
    return false, "marker-owner-election-pending", owner
  end
  if not owner then return false, "marker-owner-unavailable", nil end
  if canonical(owner) ~= canonical(state.localName) then return false, "marker-owner-passive", owner end
  return true, "marker-owner-active", owner
end

function Ownership:GetState()
  local owner = effectiveOwner()
  local peerCount, legacyPeerCount, incompatiblePeerCount = 0, 0, 0
  for _, peer in pairs(state.peers) do
    peerCount = peerCount + 1
    if not peerUsesHeartbeat(peer) then legacyPeerCount = legacyPeerCount + 1 end
    if not peerOwnerProtocolCompatible(peer) then incompatiblePeerCount = incompatiblePeerCount + 1 end
  end
  return {
    prefix = PREFIX,
    commAvailable = state.commAvailable,
    commFailureReason = state.commFailureReason,
    localName = state.localName,
    localEligible = state.localEligible,
    owner = owner,
    isOwner = owner and canonical(owner) == canonical(state.localName) or false,
    ownerReason = state.ownerReason,
    electionPending = inGroup() == true and state.commAvailable and not state.combatFrozen and now() < state.settlingUntil or false,
    peerCount = peerCount,
    legacyPeerCount = legacyPeerCount,
    incompatiblePeerCount = incompatiblePeerCount,
    minimumCompatibleOwnerProtocolRC = MIN_COMPATIBLE_OWNER_PROTOCOL_RC,
    combatFrozen = state.combatFrozen,
    heartbeatSeconds = HEARTBEAT_SECONDS,
    peerTTLSeconds = PEER_TTL_SECONDS,
  }
end
