local _, Addon = ...

local Tracker = {}
Addon.PullDeathTracker = Tracker

local DataUtils = Addon.DataUtils

local state = {
  initialized = false,
  routeFingerprint = nil,
  focusPullIndex = nil,
  contexts = {},
  seenGUIDs = {},
  inCombat = false,
  combatSerial = 0,
  readableDeathEvents = 0,
  restrictedDeathEvents = 0,
  ambiguousDeathEvents = 0,
  lastNPCID = nil,
  lastGUID = nil,
  lastReason = "uninitialized",
}

local function isSecret(value)
  return Addon.IsSecret and Addon.IsSecret(value) or false
end

local function parseNPCID(guid)
  if isSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
  local ok, value = pcall(function()
    return guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
      or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  end)
  if not ok then return nil end
  return DataUtils and DataUtils.PositiveInteger and DataUtils.PositiveInteger(value) or tonumber(value)
end

local function copyExpected(source)
  local result = {}
  for npcID, count in pairs(type(source) == "table" and source or {}) do
    npcID = tonumber(npcID)
    count = tonumber(count)
    if npcID and npcID > 0 and count and count > 0 then result[npcID] = math.floor(count) end
  end
  return result
end

local function currentRuntime()
  if not Addon.RuntimeController or type(Addon.RuntimeController.GetState) ~= "function" then return nil end
  local runtime = Addon.RuntimeController:GetState()
  if type(runtime) ~= "table" or type(runtime.routeFingerprint) ~= "string" or runtime.routeFingerprint == "" then return nil end
  return runtime
end

local function getPull(pullIndex)
  if not Addon.RuntimeController or type(Addon.RuntimeController.GetPullByIndex) ~= "function" then return nil end
  return Addon.RuntimeController:GetPullByIndex(pullIndex)
end

local function resetContextProgress(context, reason)
  context.observedByNPC = {}
  context.observedTotal = 0
  context.complete = false
  context.readableDeathEvents = 0
  context.restrictedDeathEvents = 0
  context.ambiguousDeathEvents = 0
  context.lastNPCID = nil
  context.lastGUID = nil
  context.lastReason = reason or "reset"
end

local function contextForPull(pullIndex, create, reason)
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  if not pullIndex then return nil end
  local runtime = currentRuntime()
  if not runtime then return nil end
  if state.routeFingerprint ~= runtime.routeFingerprint then
    state.routeFingerprint = runtime.routeFingerprint
    state.contexts = {}
    state.seenGUIDs = {}
  end
  local context = state.contexts[pullIndex]
  if context or not create then return context end
  local pull = getPull(pullIndex)
  if type(pull) ~= "table" then return nil end
  local death = type(pull.deathTracking) == "table" and pull.deathTracking or nil
  local expectedByNPC = copyExpected(death and death.expectedByNPC)
  local expectedTotal = tonumber(death and death.expectedTotal) or 0
  context = {
    contextKey = runtime.routeFingerprint..":"..tostring(pullIndex),
    routeFingerprint = runtime.routeFingerprint,
    pullIndex = pullIndex,
    expectedByNPC = expectedByNPC,
    expectedTotal = expectedTotal,
    active = false,
    combatSerial = state.combatSerial,
    status = death and death.available == true and expectedTotal > 0 and next(expectedByNPC) and "tracking" or "unavailable",
  }
  resetContextProgress(context, reason or (death and death.mode) or "death-tracking-unavailable")
  if context.status == "unavailable" then context.lastReason = death and death.mode or "death-tracking-unavailable" end
  state.contexts[pullIndex] = context
  return context
end

local function resetAll(reason)
  state.contexts = {}
  state.seenGUIDs = {}
  state.readableDeathEvents = 0
  state.restrictedDeathEvents = 0
  state.ambiguousDeathEvents = 0
  state.lastNPCID = nil
  state.lastGUID = nil
  state.lastReason = reason or "reset"
end

local function notifyProgress(reason)
  if Addon.MarkerExecutor and type(Addon.MarkerExecutor.OnPullDeathProgress) == "function" then
    Addon.MarkerExecutor:OnPullDeathProgress(reason or state.lastReason)
  end
end

local function markRestrictedForActiveContexts(reason)
  state.restrictedDeathEvents = state.restrictedDeathEvents + 1
  state.lastReason = reason or "combat-log-restricted"
  for _, context in pairs(state.contexts) do
    if context.active then
      context.restrictedDeathEvents = (context.restrictedDeathEvents or 0) + 1
      context.lastReason = state.lastReason
    end
  end
  notifyProgress(state.lastReason)
  return false, state.lastReason
end

local function combatLogReader()
  -- Retail 12.1 keeps the underlying C_CombatLog reader even when the old
  -- CombatLogGetCurrentEventInfo global is not installed by deprecation
  -- fallbacks. Prefer the current namespace and retain the global only for
  -- older-compatible clients/mocks.
  if type(C_CombatLog) == "table" and type(C_CombatLog.GetCurrentEventInfo) == "function" then
    return C_CombatLog.GetCurrentEventInfo
  end
  if type(CombatLogGetCurrentEventInfo) == "function" then return CombatLogGetCurrentEventInfo end
end

local function combatLogRestrictionState()
  if type(C_CombatLog) ~= "table" or type(C_CombatLog.IsCombatLogRestricted) ~= "function" then return nil end
  local ok, restricted = pcall(C_CombatLog.IsCombatLogRestricted)
  if not ok or isSecret(restricted) or type(restricted) ~= "boolean" then return nil end
  return restricted
end

local function routeBindingActive()
  return Addon.MDT and type(Addon.MDT.GetRouteBinding) == "function" and Addon.MDT:GetRouteBinding() ~= nil
end

function Tracker:RefreshContext(reason, force)
  local runtime = currentRuntime()
  if not runtime then
    state.routeFingerprint = nil
    state.focusPullIndex = nil
    resetAll(reason or "context-unavailable")
    return self:GetState()
  end
  local routeChanged = state.routeFingerprint ~= runtime.routeFingerprint
  if routeChanged or (force == true and (reason == "dungeon-run-start" or reason == "run-progress-reset"
    or reason == "route-changed" or reason == "marker-plan-changed" or reason == "initialize")) then
    state.routeFingerprint = runtime.routeFingerprint
    resetAll(reason or "route-context-changed")
  end
  state.focusPullIndex = DataUtils.PositiveInteger(runtime.currentPullIndex)
  if state.focusPullIndex then contextForPull(state.focusPullIndex, true, reason) end
  return self:GetState()
end

function Tracker:Initialize()
  state.initialized = true
  return self:RefreshContext("initialize", true)
end

function Tracker:OnCombatStarted()
  state.inCombat = true
  state.combatSerial = state.combatSerial + 1
  resetAll("combat-start")
  local runtime = currentRuntime()
  state.routeFingerprint = runtime and runtime.routeFingerprint or state.routeFingerprint
  state.focusPullIndex = runtime and DataUtils.PositiveInteger(runtime.currentPullIndex) or nil
  -- Bound-route mode activates a pull only when its dedicated route macro is
  -- actually pressed. This prevents an intentionally skipped pull from being
  -- treated as active merely because it was the UI cursor at combat start.
  if not routeBindingActive() and state.focusPullIndex then
    self:ActivatePull(state.focusPullIndex, "combat-start")
  end
  return self:GetState()
end

function Tracker:OnCombatEnded()
  state.inCombat = false
  state.lastReason = "combat-ended"
  return self:GetState()
end

function Tracker:ActivatePull(pullIndex, reason)
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  local context = contextForPull(pullIndex, true, reason or "pull-activated")
  if not context then return nil, "pull-death-context-unavailable" end
  if context.combatSerial ~= state.combatSerial then
    context.combatSerial = state.combatSerial
    resetContextProgress(context, reason or "pull-activated")
  end
  context.active = true
  state.focusPullIndex = pullIndex
  context.lastReason = reason or "pull-activated"
  state.lastReason = context.lastReason
  return self:GetState(pullIndex)
end

function Tracker:RetirePull(pullIndex, reason)
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  local context = pullIndex and state.contexts[pullIndex] or nil
  if not context then return false, "pull-death-context-unavailable" end
  context.active = false
  context.lastReason = reason or "pull-retired"
  state.lastReason = context.lastReason
  return true
end

function Tracker:OnCombatLogEvent()
  if not state.inCombat then return false, "outside-combat" end
  if combatLogRestrictionState() == true then
    return markRestrictedForActiveContexts("combat-log-restricted")
  end
  local reader = combatLogReader()
  if type(reader) ~= "function" then
    return markRestrictedForActiveContexts("combat-log-api-unavailable")
  end

  local ok, _, subevent, _, _, _, _, _, destGUID = pcall(reader)
  if not ok then
    return markRestrictedForActiveContexts("combat-log-read-failed")
  end
  if isSecret(subevent) then
    return markRestrictedForActiveContexts("combat-log-subevent-secret")
  end
  if subevent ~= "UNIT_DIED" and subevent ~= "UNIT_DESTROYED" then return false, "irrelevant-event" end

  if isSecret(destGUID) or type(destGUID) ~= "string" then
    return markRestrictedForActiveContexts("combat-log-dest-guid-secret")
  end
  if state.seenGUIDs[destGUID] then return false, "death-already-counted" end

  local npcID = parseNPCID(destGUID)
  if not npcID then return false, "death-npc-unavailable" end
  local candidates = {}
  for _, context in pairs(state.contexts) do
    if context.active and (context.status == "tracking" or context.status == "complete") then
      local expected = tonumber(context.expectedByNPC[npcID]) or 0
      local observed = tonumber(context.observedByNPC[npcID]) or 0
      if expected > observed then candidates[#candidates + 1] = context end
    end
  end
  if #candidates == 0 then return false, "death-not-active-pull-npc" end

  state.seenGUIDs[destGUID] = true
  state.lastNPCID = npcID
  state.lastGUID = destGUID
  if #candidates > 1 then
    state.ambiguousDeathEvents = state.ambiguousDeathEvents + 1
    state.lastReason = "death-npc-ambiguous-between-active-pulls"
    for _, context in ipairs(candidates) do
      context.ambiguousDeathEvents = (context.ambiguousDeathEvents or 0) + 1
      context.lastNPCID = npcID
      context.lastGUID = destGUID
      context.lastReason = state.lastReason
    end
    notifyProgress(state.lastReason)
    return false, state.lastReason
  end

  local context = candidates[1]
  local expected = tonumber(context.expectedByNPC[npcID]) or 0
  context.observedByNPC[npcID] = math.min(expected, (tonumber(context.observedByNPC[npcID]) or 0) + 1)
  context.readableDeathEvents = (context.readableDeathEvents or 0) + 1
  context.lastNPCID = npcID
  context.lastGUID = destGUID
  state.readableDeathEvents = state.readableDeathEvents + 1

  local total = 0
  local complete = true
  for expectedNPC, expectedCount in pairs(context.expectedByNPC) do
    local count = tonumber(context.observedByNPC[expectedNPC]) or 0
    total = total + math.min(expectedCount, count)
    if count < expectedCount then complete = false end
  end
  context.observedTotal = total
  context.complete = complete and total >= context.expectedTotal
  if context.complete then
    context.status = "complete"
    context.lastReason = "expected-pull-deaths-observed"
  else
    context.status = "tracking"
    context.lastReason = "pull-death-progress"
  end
  state.lastReason = context.lastReason
  notifyProgress(context.lastReason)
  return true, context.lastReason
end

function Tracker:GetCompletionVerdict(pullIndex)
  pullIndex = DataUtils.PositiveInteger(pullIndex) or state.focusPullIndex
  local context = pullIndex and state.contexts[pullIndex] or nil
  if not context then return false, "death-tracking-no-context" end
  if context.status == "complete" and context.complete then return true, "death-complete" end
  if (tonumber(context.ambiguousDeathEvents) or 0) > 0 then return nil, "death-tracking-ambiguous-overlap" end
  if context.status == "tracking" and context.expectedTotal > 0 then
    if (tonumber(context.readableDeathEvents) or 0) > 0 then return false, "death-incomplete" end
    if (tonumber(context.restrictedDeathEvents) or 0) > 0 then return nil, "death-tracking-restricted" end
    return false, "death-tracking-no-evidence"
  end
  return false, "death-tracking-unavailable"
end

local function contextState(context)
  if type(context) ~= "table" then return nil end
  local expected, observed = {}, {}
  for npcID, count in pairs(context.expectedByNPC or {}) do expected[npcID] = count end
  for npcID, count in pairs(context.observedByNPC or {}) do observed[npcID] = count end
  return {
    contextKey = context.contextKey,
    routeFingerprint = context.routeFingerprint,
    pullIndex = context.pullIndex,
    active = context.active == true,
    status = context.status,
    expectedByNPC = expected,
    expectedTotal = context.expectedTotal or 0,
    observedByNPC = observed,
    observedTotal = context.observedTotal or 0,
    complete = context.complete == true,
    readableDeathEvents = context.readableDeathEvents or 0,
    restrictedDeathEvents = context.restrictedDeathEvents or 0,
    ambiguousDeathEvents = context.ambiguousDeathEvents or 0,
    lastNPCID = context.lastNPCID,
    lastReason = context.lastReason,
  }
end

function Tracker:GetState(pullIndex)
  pullIndex = DataUtils.PositiveInteger(pullIndex) or state.focusPullIndex
  local focused = contextState(pullIndex and state.contexts[pullIndex] or nil) or {
    contextKey = nil,
    routeFingerprint = state.routeFingerprint,
    pullIndex = pullIndex,
    active = false,
    status = "idle",
    expectedByNPC = {},
    expectedTotal = 0,
    observedByNPC = {},
    observedTotal = 0,
    complete = false,
    readableDeathEvents = 0,
    restrictedDeathEvents = 0,
    ambiguousDeathEvents = 0,
    lastNPCID = nil,
    lastReason = state.lastReason,
  }
  local activePulls = {}
  for _, context in pairs(state.contexts) do
    if context.active then activePulls[#activePulls + 1] = contextState(context) end
  end
  table.sort(activePulls, function(left, right) return tonumber(left.pullIndex) < tonumber(right.pullIndex) end)
  focused.initialized = state.initialized
  focused.inCombat = state.inCombat
  focused.combatSerial = state.combatSerial
  focused.activePulls = activePulls
  focused.activeCount = #activePulls
  focused.totalReadableDeathEvents = state.readableDeathEvents
  focused.totalRestrictedDeathEvents = state.restrictedDeathEvents
  focused.totalAmbiguousDeathEvents = state.ambiguousDeathEvents
  focused.lastGUID = state.lastGUID
  return focused
end