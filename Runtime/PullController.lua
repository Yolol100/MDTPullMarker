local _, Addon = ...

local Controller = {}
Addon.RuntimeController = Controller

local DataUtils = Addon.DataUtils

local state = {
  status = "uninitialized",
  plan = nil,
  routeMacroPlan = nil,
  findings = {},
  currentPullPosition = 1,
  currentInstructionPosition = 1,
  completedPulls = {},
  skippedPulls = {},
  engagedPulls = {},
  confirmedAssignments = {},
  submittedAssignments = {},
  activeFingerprint = nil,
  activePlanSignature = nil,
  lastError = nil,
  lastRouteMacroError = nil,
  lastMarkerResult = nil,
}

local function copy(value)
  return DataUtils.DeepCopy(value)
end

local function refreshMarkerInstruction(reason)
  return Addon.MarkerExecutor:OnInstructionChanged(reason or "runtime-instruction-changed")
end

local function refreshDeathTracker(reason, force)
  return Addon.PullDeathTracker:RefreshContext(reason or "runtime-pull-changed", force == true)
end

local function currentPull()
  local plan = state.plan
  return plan and plan.pulls and plan.pulls[state.currentPullPosition] or nil
end

local function assignmentsForPull(pull)
  return type(pull) == "table" and type(pull.assignments) == "table" and pull.assignments or {}
end

local function buildPlanSignature(plan)
  local parts = { tostring(plan and plan.routeFingerprint or "no-route") }
  for _, pull in ipairs((plan and plan.pulls) or {}) do
    parts[#parts + 1] = "p="..tostring(pull.index)
    local death = type(pull.deathTracking) == "table" and pull.deathTracking or nil
    if death then
      parts[#parts + 1] = "d="..tostring(death.expectedTotal or 0)
      local ids = {}
      for npcID in pairs(type(death.expectedByNPC) == "table" and death.expectedByNPC or {}) do ids[#ids + 1] = tonumber(npcID) or 0 end
      table.sort(ids)
      for _, npcID in ipairs(ids) do
        parts[#parts + 1] = ("n=%d:%d"):format(npcID, tonumber(death.expectedByNPC[npcID]) or 0)
      end
    end
    for _, assignment in ipairs(assignmentsForPull(pull)) do
      parts[#parts + 1] = table.concat({
        tostring(assignment.id or "no-id"),
        tostring(assignment.marker or 0),
        tostring(assignment.requestedMarker or assignment.marker or 0),
        assignment.markerRemapped == true and "1" or "0",
        assignment.automaticTargeting == false and "manual" or "auto",
        tostring(assignment.priority or 0),
        tostring(assignment.batchIndex or 0),
        tostring(assignment.batchPosition or 0),
        tostring(assignment.executionMethod or ""),
        assignment.useSetUnmarked == true and "1" or "0",
        tostring(assignment.duplicateGroupName or ""),
        tostring(assignment.duplicateNameOrdinal or 1),
        tostring(assignment.npcID or 0),
        tostring(assignment.duplicateTotal or 1),
        tostring(assignment.routeNameTotal or 1),
        tostring(assignment.dungeonNameTotal or 0),
        tostring(assignment.targetNameTotal or assignment.routeNameTotal or 1),
        tostring(assignment.adjacentPullNameTotal or 0),
        tostring(assignment.routeTargetNameTotal or 0),
        tostring(assignment.otherPullNameTotal or 0),
        tostring(assignment.targetNameScope or ""),
        tostring(assignment.targetName or assignment.name or ""),
        assignment.enabled == false and "0" or "1",
      }, "\31")
    end
  end
  local canonical = table.concat(parts, "\30")
  return DataUtils and DataUtils.StableHash and DataUtils.StableHash(canonical) or canonical
end

local function confirmedForPull(pull)
  if not pull then return {} end
  state.confirmedAssignments[pull.index] = state.confirmedAssignments[pull.index] or {}
  return state.confirmedAssignments[pull.index]
end

local function submittedForPull(pull)
  if not pull then return {} end
  state.submittedAssignments[pull.index] = state.submittedAssignments[pull.index] or {}
  return state.submittedAssignments[pull.index]
end

local function markerPoolForPull(pull)
  local result = {}
  for marker = 1, 8 do result[marker] = { marker = marker, status = "available" } end
  if not pull then return result end
  local confirmed = confirmedForPull(pull)
  local submitted = submittedForPull(pull)
  for _, assignment in ipairs(assignmentsForPull(pull)) do
    local marker = tonumber(assignment.marker)
    if marker and marker >= 1 and marker <= 8 then
      local status = "reserved"
      if assignment.id and confirmed[tostring(assignment.id)] then
        status = "confirmed"
      elseif assignment.id and submitted[tostring(assignment.id)] then
        status = "submitted"
      end
      result[marker] = {
        marker = marker,
        status = status,
        assignmentID = assignment.id,
        targetName = assignment.targetName or assignment.name,
      }
    end
  end
  return result
end

local function firstUnconfirmedPosition(pull)
  local assignments = assignmentsForPull(pull)
  local confirmed = confirmedForPull(pull)
  for position, assignment in ipairs(assignments) do
    if not assignment.id or not confirmed[assignment.id] then return position end
  end
  return math.max(1, #assignments)
end

local function resetCursor()
  state.currentInstructionPosition = 1
  local pull = currentPull()
  if pull and #assignmentsForPull(pull) > 0 then
    state.currentInstructionPosition = firstUnconfirmedPosition(pull)
  end
end

local function clampPullPosition()
  local count = state.plan and #(state.plan.pulls or {}) or 0
  if count == 0 then
    state.currentPullPosition = 1
    return
  end
  if state.currentPullPosition < 1 then state.currentPullPosition = 1 end
  if state.currentPullPosition > count then state.currentPullPosition = count end
end

local function updateStatus()
  if not state.plan or state.plan.status == "blocked" then
    state.status = "blocked"
    return
  end
  local pull = currentPull()
  if not pull then
    state.status = "empty"
    return
  end
  if pull.status == "manual-required" and not state.completedPulls[pull.index] then
    state.status = "manual-required"
    return
  end
  state.status = state.completedPulls[pull.index] and "completed" or "ready"
end

local function firstFindingCode(findings)
  if type(findings) == "table" and type(findings[1]) == "table" then
    return tostring(findings[1].code or findings[1].severity or "marker-plan-unavailable")
  end
  return tostring(findings or "marker-plan-unavailable")
end

function Controller:Refresh(reason, useCurrentSnapshot)
  local snapshot, refreshError
  if useCurrentSnapshot then
    snapshot = Addon.MDT:GetSnapshot()
  else
    snapshot, refreshError = Addon.MDT:Refresh(reason or "runtime-refresh")
    if not snapshot then
      state.plan = nil
      state.routeMacroPlan = nil
      state.findings = {}
      state.lastError = tostring(refreshError or "route-unavailable")
      state.lastRouteMacroError = state.lastError
      updateStatus()
      refreshMarkerInstruction("route-unavailable")
      return nil, state.lastError
    end
  end

  local plan, findings = Addon.MDT:BuildMarkerPlan()
  if not plan then
    state.plan = nil
    state.routeMacroPlan = nil
    state.findings = findings or {}
    state.lastError = firstFindingCode(findings)
    state.lastRouteMacroError = state.lastError
    updateStatus()
    refreshMarkerInstruction("marker-plan-unavailable")
    return nil, state.lastError
  end

  local previousPull = currentPull() and currentPull().index
  local nextPlanSignature = buildPlanSignature(plan)
  local routeChanged = state.activeFingerprint and state.activeFingerprint ~= plan.routeFingerprint
  local markerPlanChanged = state.activePlanSignature and state.activePlanSignature ~= nextPlanSignature
  if routeChanged or markerPlanChanged then
    state.completedPulls = {}
    state.skippedPulls = {}
    state.engagedPulls = {}
    state.confirmedAssignments = {}
    state.submittedAssignments = {}
    state.lastMarkerResult = nil
    if routeChanged then previousPull = nil end
  end

  state.activeFingerprint = plan.routeFingerprint
  state.activePlanSignature = nextPlanSignature
  state.plan = plan
  state.findings = findings or {}
  state.routeMacroPlan = nil
  state.lastRouteMacroError = nil
  if plan.status ~= "blocked" and Addon.RouteMacroPlan and type(Addon.RouteMacroPlan.Build) == "function" then
    local routeMacroPlan, routeMacroError = Addon.RouteMacroPlan.Build(plan)
    state.routeMacroPlan = routeMacroPlan
    state.lastRouteMacroError = routeMacroError
  elseif plan.status == "blocked" then
    state.lastRouteMacroError = "marker-plan-blocked"
  else
    state.lastRouteMacroError = "route-macro-planner-unavailable"
  end

  if routeChanged then state.currentPullPosition = 1 end
  local preferredPull = not routeChanged and (previousPull or (snapshot and snapshot.currentPull)) or nil
  if preferredPull then
    for position, pull in ipairs(plan.pulls or {}) do
      if pull.index == preferredPull then
        state.currentPullPosition = position
        break
      end
    end
  end

  clampPullPosition()
  resetCursor()
  state.lastError = nil
  updateStatus()
  local refreshReason = routeChanged and "route-changed" or (markerPlanChanged and "marker-plan-changed" or (reason or "runtime-refreshed"))
  refreshDeathTracker(refreshReason, routeChanged or markerPlanChanged)
  refreshMarkerInstruction(refreshReason)
  return self:GetState()
end

function Controller:Initialize()
  state.status = "initializing"
  return self:Refresh("runtime-initialize", true)
end

function Controller:ResetProgress(reason)
  state.completedPulls = {}
  state.skippedPulls = {}
  state.engagedPulls = {}
  state.confirmedAssignments = {}
  state.submittedAssignments = {}
  state.currentPullPosition = 1
  state.currentInstructionPosition = 1
  state.lastMarkerResult = nil
  clampPullPosition()
  resetCursor()
  updateStatus()
  refreshDeathTracker(reason or "run-progress-reset", true)
  refreshMarkerInstruction(reason or "run-progress-reset")
  return self:GetState()
end

function Controller:GetPullByIndex(pullIndex)
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  if not pullIndex or not state.plan then return nil end
  for _, pull in ipairs(state.plan.pulls or {}) do
    if tonumber(pull.index) == pullIndex then return copy(pull) end
  end
end

function Controller:GetPullPositionByIndex(pullIndex)
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  if not pullIndex or not state.plan then return nil end
  for position, pull in ipairs(state.plan.pulls or {}) do
    if tonumber(pull.index) == pullIndex then return position end
  end
end

function Controller:GetRouteMacroPlan()
  return Addon.RouteMacroPlan and Addon.RouteMacroPlan.Copy and Addon.RouteMacroPlan.Copy(state.routeMacroPlan)
    or copy(state.routeMacroPlan)
end

function Controller:ResolveRouteMacroToken(token)
  if not Addon.RouteMacroPlan or type(Addon.RouteMacroPlan.ResolveToken) ~= "function" then
    return nil, "route-macro-planner-unavailable"
  end
  local descriptor = Addon.RouteMacroPlan.ResolveToken(state.routeMacroPlan, token)
  if not descriptor then return nil, "route-macro-token-unavailable" end
  return descriptor
end

function Controller:GetRouteMacroDescriptor(pullIndex, batchIndex)
  if not Addon.RouteMacroPlan or type(Addon.RouteMacroPlan.GetDescriptor) ~= "function" then
    return nil, "route-macro-planner-unavailable"
  end
  local descriptor = Addon.RouteMacroPlan.GetDescriptor(state.routeMacroPlan, pullIndex, batchIndex)
  if not descriptor then return nil, "route-macro-descriptor-unavailable" end
  return descriptor
end

function Controller:GetOrderedAssignments()
  local pull = currentPull()
  local confirmed = confirmedForPull(pull)
  local result = {}
  for position, source in ipairs(assignmentsForPull(pull)) do
    local assignment = copy(source)
    if assignment then
      assignment.instructionPosition = position
      assignment.confirmed = assignment.id and confirmed[assignment.id] == true or false
      result[#result + 1] = assignment
    end
  end
  return result
end

function Controller:SetPullByPosition(position, reason)
  position = DataUtils.PositiveInteger(position)
  if not position or not state.plan or not state.plan.pulls[position] then return nil, "pull-position-invalid" end
  local previousPosition = state.currentPullPosition
  local targetPull = state.plan.pulls[position]
  if reason == "route-macro" then
    state.engagedPulls[targetPull.index] = true
    state.skippedPulls[targetPull.index] = nil
    if previousPosition and position > previousPosition then
      -- The UI cursor can point at a pull that was never actually engaged. If
      -- the first route macro used is a later pull, that cursor pull is skipped
      -- too. Already-engaged chain-pulled packs are retained instead.
      for skippedPosition = previousPosition, position - 1 do
        local skipped = state.plan.pulls[skippedPosition]
        if skipped and not state.completedPulls[skipped.index] and not state.engagedPulls[skipped.index] then
          state.skippedPulls[skipped.index] = true
        end
      end
    end
  end
  state.currentPullPosition = position
  resetCursor()
  state.lastMarkerResult = nil
  updateStatus()
  refreshDeathTracker(reason or "pull-changed", false)
  refreshMarkerInstruction(reason or "pull-changed")
  return self:GetState()
end

function Controller:SetPullByIndex(pullIndex, reason)
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  if not pullIndex or not state.plan then return nil, "pull-index-invalid" end
  for position, pull in ipairs(state.plan.pulls or {}) do
    if pull.index == pullIndex then return self:SetPullByPosition(position, reason) end
  end
  return nil, "pull-not-found"
end

function Controller:NextPull()
  if not state.plan then return nil, "plan-unavailable" end
  if state.currentPullPosition >= #(state.plan.pulls or {}) then return nil, "last-pull" end
  return self:SetPullByPosition(state.currentPullPosition + 1)
end

function Controller:PreviousPull()
  if state.currentPullPosition <= 1 then return nil, "first-pull" end
  return self:SetPullByPosition(state.currentPullPosition - 1)
end

function Controller:CompletePullByIndex(pullIndex, options)
  if not state.plan or state.plan.status == "blocked" then return nil, "plan-blocked" end
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  local position = self:GetPullPositionByIndex(pullIndex)
  if not position then return nil, "pull-not-found" end
  options = type(options) == "table" and options or {}
  state.completedPulls[pullIndex] = true
  state.skippedPulls[pullIndex] = nil
  state.engagedPulls[pullIndex] = true
  if Addon.PullDeathTracker and type(Addon.PullDeathTracker.RetirePull) == "function" then
    Addon.PullDeathTracker:RetirePull(pullIndex, "pull-completed")
  end
  updateStatus()
  if options.advance == true and position == state.currentPullPosition and position < #(state.plan.pulls or {}) then
    return self:SetPullByPosition(position + 1, "pull-completed")
  end
  if options.silent ~= true then refreshMarkerInstruction("pull-completed") end
  return self:GetState()
end

function Controller:CompleteCurrentPull(advance)
  local pull = currentPull()
  if not pull then return nil, "pull-unavailable" end
  return self:CompletePullByIndex(pull.index, { advance = advance == true })
end

function Controller:ReopenCurrentPull()
  local pull = currentPull()
  if not pull then return nil, "pull-unavailable" end
  state.completedPulls[pull.index] = nil
  state.skippedPulls[pull.index] = nil
  updateStatus()
  refreshDeathTracker("pull-reopened", true)
  refreshMarkerInstruction("pull-reopened")
  return self:GetState()
end

function Controller:NextInstruction()
  local assignments = assignmentsForPull(currentPull())
  if #assignments == 0 then return nil, "pull-unavailable" end
  if state.currentInstructionPosition >= #assignments then return nil, "last-instruction" end
  state.currentInstructionPosition = state.currentInstructionPosition + 1
  state.lastMarkerResult = nil
  refreshMarkerInstruction("instruction-changed")
  return self:GetState()
end

function Controller:PreviousInstruction()
  if not currentPull() then return nil, "pull-unavailable" end
  if state.currentInstructionPosition <= 1 then return nil, "first-instruction" end
  state.currentInstructionPosition = state.currentInstructionPosition - 1
  state.lastMarkerResult = nil
  refreshMarkerInstruction("instruction-changed")
  return self:GetState()
end

function Controller:OnMarkerApplied(markerIndex, assignmentID)
  if not state.plan or state.plan.status == "blocked" then return nil, "plan-blocked" end
  local pull = currentPull()
  if not pull then return nil, "pull-unavailable" end
  local assignments = assignmentsForPull(pull)
  local position = state.currentInstructionPosition
  local assignment = assignments[position]
  if not assignment then return nil, "instruction-unavailable" end

  if assignmentID ~= nil and tostring(assignmentID) ~= tostring(assignment.id) then
    state.lastMarkerResult = {
      status = "unexpected-assignment",
      expectedAssignmentID = assignment.id,
      observedAssignmentID = tostring(assignmentID),
      marker = tonumber(markerIndex),
    }
    return nil, "assignment-mismatch"
  end

  markerIndex = tonumber(markerIndex)
  if markerIndex ~= tonumber(assignment.marker) then
    state.lastMarkerResult = {
      status = "unexpected",
      expected = tonumber(assignment.marker),
      observed = markerIndex,
      assignmentID = assignment.id,
    }
    return nil, "unexpected-marker"
  end

  local confirmed = confirmedForPull(pull)
  if assignment.id then confirmed[assignment.id] = true end
  state.lastMarkerResult = {
    status = "confirmed",
    marker = markerIndex,
    assignmentID = assignment.id,
    pullIndex = pull.index,
  }

  local global = Addon.Database.GetGlobal()
  if not global or global.autoAdvanceInstructions ~= false then
    for nextPosition = position + 1, #assignments do
      local nextAssignment = assignments[nextPosition]
      if not nextAssignment.id or not confirmed[nextAssignment.id] then
        state.currentInstructionPosition = nextPosition
        return self:GetState(), "instruction-confirmed"
      end
    end
  end

  local allConfirmed = #assignments > 0
  for _, candidate in ipairs(assignments) do
    if not candidate.id or not confirmed[candidate.id] then
      allConfirmed = false
      break
    end
  end
  return self:GetState(), allConfirmed and "all-instructions-confirmed" or "instruction-confirmed"
end

function Controller:OnBatchSubmitted(items)
  if not state.plan or state.plan.status == "blocked" then return nil, "plan-blocked" end
  local pull = currentPull()
  if not pull then return nil, "pull-unavailable" end
  if type(items) ~= "table" or #items == 0 then return nil, "bulk-items-empty" end

  local valid = {}
  for _, assignment in ipairs(assignmentsForPull(pull)) do
    if assignment.id then valid[tostring(assignment.id)] = tonumber(assignment.marker) end
  end
  local submitted = submittedForPull(pull)
  for _, item in ipairs(items) do
    local assignmentID = tostring(item and item.assignmentID or "")
    local marker = tonumber(item and item.marker)
    if assignmentID == "" or valid[assignmentID] ~= marker then return nil, "assignment-mismatch" end
  end
  for _, item in ipairs(items) do submitted[tostring(item.assignmentID)] = true end
  return self:GetState(), "batch-submitted"
end

local function pullIndexList(source)
  local result = {}
  for pullIndex, enabled in pairs(source or {}) do
    pullIndex = tonumber(pullIndex)
    if enabled == true and pullIndex then result[#result + 1] = pullIndex end
  end
  table.sort(result)
  return result
end

function Controller:GetState()
  local pull = currentPull()
  local assignments = assignmentsForPull(pull)
  local assignment = assignments[state.currentInstructionPosition]
  local confirmed = confirmedForPull(pull)
  local confirmedCount = 0
  for _, candidate in ipairs(assignments) do
    if candidate.id and confirmed[candidate.id] then confirmedCount = confirmedCount + 1 end
  end

  return {
    status = state.status,
    planStatus = state.plan and state.plan.status or "unavailable",
    routeKey = state.plan and state.plan.routeKey,
    dungeonName = state.plan and state.plan.dungeonName,
    presetName = state.plan and state.plan.presetName,
    routeFingerprint = state.plan and state.plan.routeFingerprint,
    observedFingerprint = state.plan and state.plan.observedFingerprint,
    currentPullPosition = state.currentPullPosition,
    currentPullIndex = pull and pull.index,
    pullCount = state.plan and #(state.plan.pulls or {}) or 0,
    routePullCount = state.plan and state.plan.summary and state.plan.summary.routePulls or 0,
    routeMarkerCount = state.plan and state.plan.summary and state.plan.summary.assignments or 0,
    routeMacroCount = state.routeMacroPlan and state.routeMacroPlan.summary and state.routeMacroPlan.summary.macroCount or 0,
    routeMacroManualPulls = state.routeMacroPlan and state.routeMacroPlan.summary and state.routeMacroPlan.summary.manualPulls or 0,
    routeMacroPlanError = state.lastRouteMacroError,
    assignmentCount = #assignments,
    instructionPosition = assignment and state.currentInstructionPosition or 0,
    instructionCount = #assignments,
    confirmedCount = confirmedCount,
    allAssignmentsConfirmed = #assignments > 0 and confirmedCount == #assignments,
    assignment = copy(assignment),
    assignmentConfirmed = assignment and assignment.id and confirmed[assignment.id] == true or false,
    completed = pull and state.completedPulls[pull.index] == true or false,
    skipped = pull and state.skippedPulls[pull.index] == true or false,
    completedPulls = pullIndexList(state.completedPulls),
    skippedPulls = pullIndexList(state.skippedPulls),
    engagedPulls = pullIndexList(state.engagedPulls),
    pullStatus = pull and pull.status or nil,
    automaticTargeting = pull and pull.automaticTargeting ~= false or false,
    markerPool = copy(markerPoolForPull(pull)),
    deathTracking = Addon.PullDeathTracker:GetState(),
    findings = copy(state.findings),
    lastMarkerResult = copy(state.lastMarkerResult),
    lastError = state.lastError,
  }
end
