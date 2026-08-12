local _, Addon = ...

local Session = {}
Addon.DungeonSession = Session

local DataUtils = Addon.DataUtils

local state = {
  active = false,
  inInstance = false,
  instanceType = nil,
  instanceName = nil,
  difficultyID = nil,
  difficultyName = nil,
  difficultyMode = nil,
  challengeMapID = nil,
  challengeName = nil,
  isMythicPlus = false,
  routeName = nil,
  routeChallengeMapID = nil,
  routeMatches = nil,
  markerCount = 0,
  challengeCompleted = false,
  lastReason = nil,
  lastAction = nil,
  lastError = nil,
  serial = 0,
}

local function copy(value)
  return DataUtils.DeepCopy(value)
end

local function safeCall(callable, ...)
  if type(callable) ~= "function" then return nil end
  local ok, first, second, third, fourth, fifth, sixth, seventh, eighth = pcall(callable, ...)
  if not ok then return nil end
  local function scrub(value)
    if Addon.IsSecret and Addon.IsSecret(value) then return nil end
    return value
  end
  return scrub(first), scrub(second), scrub(third), scrub(fourth), scrub(fifth), scrub(sixth), scrub(seventh), scrub(eighth)
end

local function positiveInteger(value)
  return DataUtils and DataUtils.PositiveInteger(value) or nil
end

local function normalizeName(value)
  return DataUtils and DataUtils.NormalizeName(value) or nil
end

local function namesMatch(left, right)
  left, right = normalizeName(left), normalizeName(right)
  if not left or not right then return nil end
  return left == right
end

local function routeMatchesSession(plan, session)
  local routeMapID = plan and positiveInteger(plan.challengeMapID)
  local activeMapID = session and positiveInteger(session.challengeMapID)
  if routeMapID and activeMapID then return routeMapID == activeMapID end
  return namesMatch(plan and plan.dungeonName, session and (session.challengeName or session.instanceName))
end

local function readInstance()
  local inInstance, instanceType = safeCall(IsInInstance)
  local name, _, difficultyID = safeCall(GetInstanceInfo)
  local difficultyName
  if difficultyID and type(GetDifficultyInfo) == "function" then difficultyName = safeCall(GetDifficultyInfo, difficultyID) end
  local challengeMapID
  if type(C_ChallengeMode) == "table" then challengeMapID = positiveInteger(safeCall(C_ChallengeMode.GetActiveChallengeMapID)) end
  local challengeName
  if challengeMapID and type(C_ChallengeMode) == "table" and type(C_ChallengeMode.GetMapUIInfo) == "function" then
    challengeName = safeCall(C_ChallengeMode.GetMapUIInfo, challengeMapID)
  end
  local isDungeon = inInstance == true and (instanceType == "party" or challengeMapID ~= nil)
  return {
    active = isDungeon,
    inInstance = inInstance == true,
    instanceType = instanceType,
    instanceName = name,
    difficultyID = not (Addon.IsSecret and Addon.IsSecret(difficultyID)) and tonumber(difficultyID) or nil,
    difficultyName = type(difficultyName) == "string" and difficultyName or nil,
    difficultyMode = challengeMapID and "mythic-plus" or (type(difficultyName) == "string" and DataUtils.NormalizeName(difficultyName) or "dungeon"),
    challengeMapID = challengeMapID,
    challengeName = challengeName,
    isMythicPlus = challengeMapID ~= nil,
  }
end

local function getPlan()
  if not Addon.MDT or type(Addon.MDT.BuildMarkerPlan) ~= "function" then return nil end
  return Addon.MDT:BuildMarkerPlan()
end

local function shouldOpen(global, session, plan)
  if global.autoOpenRuntime == false then return false, "auto-open-disabled" end
  if not session.active then return false, "outside-dungeon" end
  if session.challengeCompleted then return false, "challenge-completed" end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "combat-lockdown" end
  local markerCount = plan and plan.summary and tonumber(plan.summary.assignments) or 0
  if global.openOnlyWithMarkers ~= false and markerCount <= 0 then return false, "no-route-markers" end
  local match = routeMatchesSession(plan, session)
  if match == false then return false, "route-instance-mismatch" end
  if match ~= true then return false, "route-instance-unverified" end
  return true
end

function Session:Refresh(reason, allowWindowAction)
  local previousActive = state.active
  local current = readInstance()
  local snapshot = Addon.MDT:GetSnapshot()
  local plan = getPlan()
  local global = Addon.Database.GetGlobal()

  state.active = current.active
  state.inInstance = current.inInstance
  state.instanceType = current.instanceType
  state.instanceName = current.instanceName
  state.difficultyID = current.difficultyID
  state.difficultyName = current.difficultyName
  state.difficultyMode = current.difficultyMode
  state.challengeMapID = current.challengeMapID
  state.challengeName = current.challengeName
  state.isMythicPlus = current.isMythicPlus
  state.routeName = (plan and plan.dungeonName) or (snapshot and snapshot.dungeonName) or nil
  state.routeChallengeMapID = (plan and plan.challengeMapID) or (snapshot and snapshot.challengeMapID) or nil
  state.routeMatches = routeMatchesSession(plan or snapshot, state)
  state.markerCount = plan and plan.summary and tonumber(plan.summary.assignments) or 0
  state.lastReason = reason
  state.lastError = nil
  state.lastAction = "refreshed"
  if not state.active then state.challengeCompleted = false end

  -- A fresh dungeon run must clear both the cursor and confirmation/completion
  -- state. Merely selecting pull 1 is insufficient: confirmed assignments from a
  -- previous run of the same route would otherwise be skipped after re-entry.
  -- Challenge start/reset events define a new run as well.
  if state.active and (not previousActive or reason == "CHALLENGE_MODE_START" or reason == "CHALLENGE_MODE_RESET")
    and Addon.RuntimeController then
    if type(Addon.RuntimeController.ResetProgress) == "function" then
      Addon.RuntimeController:ResetProgress("dungeon-run-start")
    elseif type(Addon.RuntimeController.SetPullByPosition) == "function" then
      -- Compatibility fallback for partial/mocked runtimes.
      Addon.RuntimeController:SetPullByPosition(1)
    end
  end

  if allowWindowAction ~= false then
    if state.active then
      local open, why = shouldOpen(global, state, plan)
      if open and not Addon.RuntimeFrame:IsOpen() then
        local _, openError = Addon.RuntimeFrame:Open()
        state.lastAction = openError and "runtime-open-failed" or "runtime-opened"
        state.lastError = openError
      elseif open then
        state.lastAction = "runtime-already-open"
      else
        state.lastAction = why
      end
    elseif previousActive and global.autoCloseRuntime ~= false and Addon.RuntimeFrame:IsOpen() then
      Addon.RuntimeFrame:Close()
      state.lastAction = "runtime-closed"
    end
  end
  Addon.MarkerOwnership:RefreshEligibility("dungeon-session-refreshed")
  Addon.MarkerExecutor:OnInstructionChanged("dungeon-session-refreshed")
  return self:GetState()
end

function Session:ScheduleRefresh(reason, delay, allowWindowAction)
  state.serial = state.serial + 1
  local serial = state.serial
  local function run()
    if serial ~= state.serial then return end
    local instance = readInstance()
    local allowUILoad = instance.active
      and not (type(InCombatLockdown) == "function" and InCombatLockdown())
    Addon.MDT:Refresh("session:"..tostring(reason), { allowUILoad = allowUILoad })
    Addon.RuntimeController:Refresh("session:"..tostring(reason), true)
    Session:Refresh(reason, allowWindowAction)
    if Addon.ConfigurationUI:HasViews() then Addon.ConfigurationUI:Refresh() end
    if Addon.RuntimeFrame:IsOpen() then Addon.RuntimeFrame:Refresh() end
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(math.max(0, tonumber(delay) or 0), run)
  else
    run()
  end
end

function Session:OnEvent(event)
  if event == "CHALLENGE_MODE_COMPLETED" then
    state.serial = state.serial + 1
    state.challengeCompleted = true
    local global = Addon.Database.GetGlobal()
    if global.autoCloseRuntime ~= false then Addon.RuntimeFrame:Close() end
    state.lastReason = event
    state.lastAction = "challenge-completed"
    Addon.MarkerExecutor:OnInstructionChanged("challenge-completed")
    return self:GetState()
  end
  if event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_RESET" then state.challengeCompleted = false end
  local delay = event == "PLAYER_ENTERING_WORLD" and 1 or 0.2
  self:ScheduleRefresh(event, delay, true)
end

function Session:GetState() return copy(state) end
