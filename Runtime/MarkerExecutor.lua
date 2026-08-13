local _, Addon = ...

local Executor = {}
Addon.MarkerExecutor = Executor

local Constants = Addon.Constants or {}
local MarkerMacro = Addon.MarkerMacro
local SMART_BUTTON_NAME = Constants.SmartButtonName or "MDTPullMarkerSmartButton"
local SMART_MACRO_NAME = Constants.SmartMacroName or "MDTPM1"
local SECOND_SMART_MACRO_NAME = Constants.SmartMacroName2 or "MDTPM2"
local SMART_MACRO_NAMES = { SMART_MACRO_NAME, SECOND_SMART_MACRO_NAME }
local MARKER_WINDOW_SECONDS = 4
local MAX_DISTINCT_MARKS_PER_WINDOW = 3
local MARKER_CONFIRM_TIMEOUT_SECONDS = 1
local SAFE_IDLE_MACRO = MarkerMacro.SAFE_IDLE_MACRO

local smartButton
local pendingSecureRefresh = false
local recentSubmissionTimes = {}
local instructionRefreshSerial = 0
local nextInstructionReadyAt = 0
local lastResult
local lastBulkSubmissionAt = 0
local submittedBulkTokens = {}
local pendingPullAdvance
local pendingPullAdvances = {}
local pendingMarkerAttempt
local markerAttemptSerial = 0
local macroListRefreshScheduled = false
local executionInvalidated = false
local executionInvalidationReason

local function routeBindingActive() return Addon.MDT and type(Addon.MDT.GetRouteBinding) == "function" and Addon.MDT:GetRouteBinding() ~= nil end
local function getRouteMacroPlan() if not Addon.RuntimeController or type(Addon.RuntimeController.GetRouteMacroPlan) ~= "function" then return nil end return Addon.RuntimeController:GetRouteMacroPlan() end
local function log(level, message, showInChat) if Addon.Log then Addon.Log(level, message, showInChat) end end
local function isSecret(value) return Addon.IsSecret and Addon.IsSecret(value) or false end
local function monotonicTime()
  local function readClock(api) if type(api) ~= "function" then return nil end local ok, value = pcall(api) if not ok or isSecret(value) then return nil end value = tonumber(value) return value and value >= 0 and value or nil end
  return readClock(GetTimePreciseSec) or readClock(GetTime) or 0
end
local function liveDungeonActive()
  if type(IsInInstance) ~= "function" then return false end
  local ok, inInstance, instanceType = pcall(IsInInstance); if not ok or isSecret(inInstance) or isSecret(instanceType) or inInstance ~= true then return false end
  if instanceType == "party" then return true end
  if type(C_ChallengeMode) == "table" and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then local mapOK, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID) if mapOK and not isSecret(mapID) and tonumber(mapID) then return true end end
  return false
end
local function markerOwnerAllowsExecution() local owner, reason, ownerName = Addon.MarkerOwnership:IsOwner() if owner then return true, reason, ownerName end return false, reason or "marker-owner-passive", ownerName end
local function setResult(status, code, marker, source) lastResult = { status = tostring(status or "unknown"), code = code and tostring(code) or nil, marker = tonumber(marker), source = source and tostring(source) or nil, at = monotonicTime() } end
local function refreshRuntimeFrameIfOpen() if Addon.RuntimeFrame:IsOpen() then Addon.RuntimeFrame:Refresh() end end
local sanitizeTargetName = MarkerMacro.SanitizeTargetName

local function getRuntimeInstructionIdentity()
  if executionInvalidated then return nil, executionInvalidationReason or "execution-invalidated" end
  local runtimeState = Addon.RuntimeController:GetState(); if not runtimeState or runtimeState.planStatus == "blocked" then return nil, "plan-blocked" end
  local session = Addon.DungeonSession:GetState(); if not session then return nil, "dungeon-session-unavailable" end
  if session.challengeCompleted then return nil, "challenge-completed" end
  if not liveDungeonActive() or not session.active then return nil, "outside-dungeon" end
  if session.routeMatches == false then return nil, "route-instance-mismatch" end
  if session.routeMatches ~= true then return nil, "route-instance-unverified" end
  local ownerAllowed, ownerError = markerOwnerAllowsExecution(); if not ownerAllowed then return nil, ownerError end
  if runtimeState.completed then return nil, "pull-completed" end
  if runtimeState.allAssignmentsConfirmed then return nil, "pull-markers-complete" end
  if runtimeState.assignmentConfirmed then return nil, "instruction-already-confirmed" end
  local assignment = runtimeState.assignment; if not assignment then return nil, "instruction-unavailable" end
  local marker = tonumber(assignment.marker); if not marker or marker < 1 or marker > 8 then return nil, "instruction-marker-invalid" end
  local targetName, targetNameError = sanitizeTargetName(assignment.targetName or assignment.name); if not targetName then return nil, targetNameError end
  return { marker = marker, assignmentID = assignment.id, enemyIndex = tonumber(assignment.enemyIndex), cloneIndex = tonumber(assignment.cloneIndex), npcID = tonumber(assignment.npcID), duplicateTotal = tonumber(assignment.duplicateTotal) or 1, routeNameTotal = tonumber(assignment.routeNameTotal) or 1, dungeonNameTotal = tonumber(assignment.dungeonNameTotal) or 0, targetNameTotal = tonumber(assignment.targetNameTotal or assignment.routeNameTotal) or 1, targetNameScope = assignment.targetNameScope, targetName = targetName, firstMatchOnly = assignment.firstMatchOnly == true, sameNameSequence = assignment.sameNameSequence == true, requiresMouseover = assignment.requiresMouseover == true, markedNameTotal = tonumber(assignment.markedNameTotal) or 0, priority = tonumber(assignment.priority), matchPolicy = assignment.matchPolicy or "exact-name", pullIndex = runtimeState.currentPullIndex, routeFingerprint = runtimeState.routeFingerprint }
end

local BULK_MARKER_LIMIT = MarkerMacro.BULK_MARKER_LIMIT
local MAX_ROUTE_BATCHES = 3
local parseBulkToken = MarkerMacro.ParseBulkToken
local function getRuntimeBulkIdentities(batchIndex)
  if executionInvalidated then return nil, executionInvalidationReason or "execution-invalidated" end
  batchIndex = tonumber(batchIndex) or 1; if batchIndex < 1 or batchIndex > MAX_ROUTE_BATCHES then return nil, "bulk-batch-invalid" end
  if not Addon.RuntimeController or type(Addon.RuntimeController.GetState) ~= "function" or type(Addon.RuntimeController.GetOrderedAssignments) ~= "function" then return nil, "runtime-unavailable" end
  local runtimeState = Addon.RuntimeController:GetState(); if not runtimeState or runtimeState.planStatus == "blocked" then return nil, "plan-blocked" end
  local session = Addon.DungeonSession:GetState(); if not session then return nil, "dungeon-session-unavailable" end
  if session.challengeCompleted then return nil, "challenge-completed" end
  if not liveDungeonActive() or not session.active then return nil, "outside-dungeon" end
  if session.routeMatches == false then return nil, "route-instance-mismatch" end; if session.routeMatches ~= true then return nil, "route-instance-unverified" end
  local ownerAllowed, ownerError = markerOwnerAllowsExecution(); if not ownerAllowed then return nil, ownerError end
  if runtimeState.completed then return nil, "pull-completed" end
  if runtimeState.automaticTargeting == false or runtimeState.pullStatus == "manual-required" then return nil, "same-name-automatic-targeting-unavailable" end
  local result = {}
  for _, assignment in ipairs(Addon.RuntimeController:GetOrderedAssignments() or {}) do
    if assignment and tonumber(assignment.batchIndex) == batchIndex then
      local marker = tonumber(assignment.marker); if not marker or marker < 1 or marker > 8 then return nil, "instruction-marker-invalid" end
      local targetName, targetNameError = sanitizeTargetName(assignment.targetName or assignment.name); if not targetName then return nil, targetNameError end
      local executionMethod = tostring(assignment.executionMethod or "exact-name"); if executionMethod ~= "exact-name" then return nil, executionMethod == "same-name-manual" and "same-name-automatic-targeting-unavailable" or "bulk-execution-method-invalid" end
      result[#result + 1] = { marker = marker, requestedMarker = tonumber(assignment.requestedMarker) or marker, markerRemapped = assignment.markerRemapped == true, markerRemappedFrom = tonumber(assignment.markerRemappedFrom), assignmentID = assignment.id, enemyIndex = tonumber(assignment.enemyIndex), cloneIndex = tonumber(assignment.cloneIndex), npcID = tonumber(assignment.npcID), targetName = targetName, priority = tonumber(assignment.priority), pullIndex = runtimeState.currentPullIndex, routeFingerprint = runtimeState.routeFingerprint, batchIndex = batchIndex, batchPosition = tonumber(assignment.batchPosition) or (#result + 1), executionMethod = executionMethod, useSetUnmarked = true, duplicateGroupName = assignment.duplicateGroupName, duplicateNameOrdinal = tonumber(assignment.duplicateNameOrdinal) or 1, automaticTargeting = assignment.automaticTargeting ~= false, confirmed = assignment.confirmed == true }
    end
  end
  table.sort(result, function(left, right) if left.batchPosition ~= right.batchPosition then return left.batchPosition < right.batchPosition end return tostring(left.assignmentID or "") < tostring(right.assignmentID or "") end)
  if #result == 0 then if batchIndex == 2 then return nil, "bulk-second-batch-empty" end if batchIndex == 3 then return nil, "bulk-third-batch-empty" end return nil, "instruction-unavailable" end
  if #result > BULK_MARKER_LIMIT then return nil, "bulk-batch-over-capacity" end
  return result
end
local bulkTokenForIdentities = MarkerMacro.BuildBulkToken
local buildBulkMacroText = MarkerMacro.BuildBulkBody
local function desiredMacroText(batchIndex)
  batchIndex = tonumber(batchIndex) or 1; if routeBindingActive() then return SAFE_IDLE_MACRO, "bound-route-uses-precomputed-macros" end
  local identities, bulkError = getRuntimeBulkIdentities(batchIndex); if not identities then return SAFE_IDLE_MACRO, bulkError end
  local body, bodyError = buildBulkMacroText(identities); if not body then return SAFE_IDLE_MACRO, bodyError end
  local warning; if #identities < BULK_MARKER_LIMIT then if batchIndex == 2 then warning = "bulk-second-batch-fewer-than-three-targets" elseif batchIndex == 3 then warning = "bulk-third-batch-fewer-than-three-targets" else warning = "bulk-fewer-than-three-targets" end end
  return body, warning
end
local function dungeonSessionActive() local session = Addon.DungeonSession:GetState() return liveDungeonActive() and type(session) == "table" and session.active == true end
local smartMacroManager = Addon.SmartMacroManager:Create({ desiredBody = desiredMacroText, dungeonSessionActive = dungeonSessionActive, log = log, buttonName = SMART_BUTTON_NAME, macroNames = SMART_MACRO_NAMES })
local function refreshSmartMacros(reason, pickupIndex, createIfMissing) return smartMacroManager:RefreshAll(reason, pickupIndex, createIfMissing) end
local function refreshSmartMacro(reason, pickup, createIfMissing) return smartMacroManager:RefreshPrimary(reason, pickup, createIfMissing) end

local function routeMacroExecutionAllowed()
  if executionInvalidated then return false, executionInvalidationReason or "execution-invalidated" end
  local session = Addon.DungeonSession and Addon.DungeonSession:GetState() or nil
  if type(session) ~= "table" or session.active ~= true or not liveDungeonActive() then return false, "outside-dungeon" end
  if session.challengeCompleted == true then return false, "challenge-completed" end
  if session.routeMatches == false then return false, "route-instance-mismatch" end
  if session.routeMatches ~= true then return false, "route-instance-unverified" end
  local ownerAllowed, ownerError = markerOwnerAllowsExecution(); if not ownerAllowed then return false, ownerError or "marker-owner-passive" end
  return true
end
local function routePullAlreadyCompleted(runtimeState, pullIndex) pullIndex = tonumber(pullIndex); if not pullIndex or type(runtimeState) ~= "table" then return false end; if tonumber(runtimeState.currentPullIndex) == pullIndex and runtimeState.completed == true then return true end; for _, completedPullIndex in ipairs(runtimeState.completedPulls or {}) do if tonumber(completedPullIndex) == pullIndex then return true end end; return false end
local function routeMacroDescriptorsForContext()
  local routeMacroPlan = getRouteMacroPlan(); if type(routeMacroPlan) ~= "table" or type(routeMacroPlan.descriptors) ~= "table" then return nil, false, "route-macro-plan-unavailable" end
  local active, gateReason = routeMacroExecutionAllowed(); local descriptors = {}
  for _, source in ipairs(routeMacroPlan.descriptors) do local descriptor = {}; for key, value in pairs(source) do descriptor[key] = value end; if not active then descriptor.body = SAFE_IDLE_MACRO end; descriptors[#descriptors + 1] = descriptor end
  return descriptors, active, gateReason
end
local function refreshRouteMacros(reason, pickupName, createIfMissing) if not routeBindingActive() then return {}, nil end local descriptors, _, descriptorError = routeMacroDescriptorsForContext(); if not descriptors then return nil, descriptorError end return smartMacroManager:RefreshDescriptorSet(descriptors, reason, pickupName, createIfMissing == true) end
local function getRouteMacroStatus() local descriptors, active, gateReason = routeMacroDescriptorsForContext(); descriptors = descriptors or {}; local status = smartMacroManager:GetDescriptorSetStatus(descriptors); status.executionActive = active == true; status.gateReason = gateReason; return status end
local function getSmartMacroStatus(_, batchIndex) return smartMacroManager:GetStatus(batchIndex) end
local function actionUsesKeyDown() if type(C_CVar) == "table" and type(C_CVar.GetCVarBool) == "function" then local ok, value = pcall(C_CVar.GetCVarBool, "ActionButtonUseKeyDown"); if ok and not isSecret(value) then return value == true end end; if type(GetCVarBool) == "function" then local ok, value = pcall(GetCVarBool, "ActionButtonUseKeyDown"); if ok and not isSecret(value) then return value == true end end; return false end
local function configureSmartButtonClicks() if not smartButton then return nil, "button-unavailable" end; if type(InCombatLockdown) == "function" and InCombatLockdown() then pendingSecureRefresh = true; return nil, "in-combat" end; local clickType = actionUsesKeyDown() and "AnyDown" or "AnyUp"; smartButton:RegisterForClicks(clickType); return clickType end
local function applySecureConfiguration(reason)
  if not smartButton then return false, "button-unavailable" end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then pendingSecureRefresh = true; smartMacroManager:MarkPending(); return false, "in-combat" end
  local body, bodyError = desiredMacroText(); if not body then pendingSecureRefresh = true; return false, bodyError or "macro-body-unavailable" end
  smartButton:SetAttribute("type1", "macro"); smartButton:SetAttribute("macrotext1", body); pendingSecureRefresh = false; log("DEBUG", "Secure three-target bulk marker action configured: "..tostring(reason or "unspecified"), false); return true
end
local function createSmartSecureButton() if smartButton then return smartButton end; smartButton = _G[SMART_BUTTON_NAME] or CreateFrame("Button", SMART_BUTTON_NAME, UIParent, "SecureActionButtonTemplate"); smartButton:SetSize(1, 1); smartButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -120, -120); smartButton:SetAlpha(0); smartButton:EnableMouse(false); configureSmartButtonClicks(); return smartButton end
local function notifyMarkerConfirmed(markerIndex, assignmentID) if not Addon.RuntimeController or type(Addon.RuntimeController.OnMarkerApplied) ~= "function" then return nil, "runtime-unavailable" end local advanced, advanceError = Addon.RuntimeController:OnMarkerApplied(markerIndex, assignmentID); if advanced and Addon.RuntimeFrame and Addon.RuntimeFrame:IsOpen() then Addon.RuntimeFrame:Refresh() end return advanced, advanceError end
local function configureCurrentInstruction(reason)
  local secureOK, secureError = applySecureConfiguration(reason); local boundRoute = routeBindingActive(); local session = Addon.DungeonSession:GetState(); local createIfMissing = not boundRoute and (session and session.active == true or false) or false
  local macroResults, macroError = refreshSmartMacros(reason, nil, createIfMissing); local macroOK = macroResults ~= nil; local routeMacroResults, routeMacroError
  if boundRoute then routeMacroResults, routeMacroError = refreshRouteMacros(reason, nil, true) end
  local routeMacroOK = not boundRoute or routeMacroResults ~= nil
  if not secureOK and secureError ~= "button-unavailable" then log("WARN", "Secure marker action could not be refreshed: "..tostring(secureError), false) end
  if not macroOK and macroError ~= "in-combat" and macroError ~= "macro-api-unavailable" then log("WARN", "Macro refresh: "..tostring(macroError), false) end
  if not routeMacroOK and routeMacroError ~= "in-combat" and routeMacroError ~= "macro-api-unavailable" then log("WARN", "Route macro refresh: "..tostring(routeMacroError), false) end
  if not secureOK then return false, secureError or "secure-refresh-failed" end
  if not macroOK and macroError ~= "in-combat" and macroError ~= "macro-api-unavailable" then return false, macroError or "macro-refresh-failed" end
  if not routeMacroOK and routeMacroError ~= "in-combat" and routeMacroError ~= "macro-api-unavailable" then return false, routeMacroError or "route-macro-refresh-failed" end
  return true, routeMacroError or macroError
end
local function pruneSubmissionTimes(now) if not now or now <= 0 then recentSubmissionTimes = {}; return end local kept = {}; for _, submittedAt in ipairs(recentSubmissionTimes) do if now - submittedAt < MARKER_WINDOW_SECONDS then kept[#kept + 1] = submittedAt end end recentSubmissionTimes = kept end
local function recordSubmissionAndGetRefreshDelay() local now = monotonicTime(); if now <= 0 then return 0 end; pruneSubmissionTimes(now); recentSubmissionTimes[#recentSubmissionTimes + 1] = now; if #recentSubmissionTimes < MAX_DISTINCT_MARKS_PER_WINDOW then return 0 end; return math.max(0, (recentSubmissionTimes[1] + MARKER_WINDOW_SECONDS) - now) end
local function rateDelayRemaining() if nextInstructionReadyAt <= 0 then return 0 end; local now = monotonicTime(); if now <= 0 or now >= nextInstructionReadyAt then nextInstructionReadyAt = 0; return 0 end; return nextInstructionReadyAt - now end
local function scheduleInstructionRefresh(reason, delay)
  instructionRefreshSerial = instructionRefreshSerial + 1; local serial = instructionRefreshSerial; delay = math.max(0, tonumber(delay) or 0); nextInstructionReadyAt = delay > 0 and (monotonicTime() + delay) or 0
  local function refresh() if serial ~= instructionRefreshSerial then return end; nextInstructionReadyAt = 0; configureCurrentInstruction(reason or "marker-submitted"); refreshRuntimeFrameIfOpen() end
  if delay > 0 and type(C_Timer) == "table" and type(C_Timer.After) == "function" then configureCurrentInstruction("marker-rate-paced"); refreshRuntimeFrameIfOpen(); C_Timer.After(delay, refresh) else refresh() end
end
local function cancelPendingMarkerAttempt() markerAttemptSerial = markerAttemptSerial + 1; pendingMarkerAttempt = nil end

local function armDirectTarget(expectedAssignmentID, source)
  source = source or "actionbar-macro"; local identity, identityError = getRuntimeInstructionIdentity(); if not identity then setResult("failed", identityError, nil, source); refreshRuntimeFrameIfOpen(); return nil, identityError end
  if tostring(expectedAssignmentID or "") ~= tostring(identity.assignmentID or "") then setResult("failed", "assignment-mismatch", identity.marker, source); refreshRuntimeFrameIfOpen(); return nil, "assignment-mismatch" end
  markerAttemptSerial = markerAttemptSerial + 1; local serial = markerAttemptSerial; local now = monotonicTime(); pendingMarkerAttempt = { serial = serial, assignmentID = tostring(identity.assignmentID), marker = tonumber(identity.marker), unitToken = identity.requiresMouseover and "mouseover" or "target", source = source, armedAt = now, expiresAt = now > 0 and (now + MARKER_CONFIRM_TIMEOUT_SECONDS) or 0 }; setResult("armed", "marker-attempt-armed", identity.marker, source)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(MARKER_CONFIRM_TIMEOUT_SECONDS, function() local pending = pendingMarkerAttempt; if not pending or pending.serial ~= serial then return end; pendingMarkerAttempt = nil; setResult("failed", "marker-update-not-observed", pending.marker, pending.source); log("WARN", "No RAID_TARGET_UPDATE followed the marker attempt; progress was not advanced.", false); refreshRuntimeFrameIfOpen() end) end
  return true, "marker-attempt-armed"
end
local function readObservedMarker(unitToken) if type(GetRaidTargetIndex) ~= "function" then return nil, "unavailable" end; local ok, value = pcall(GetRaidTargetIndex, unitToken); if not ok then return nil, "read-failed" end; if isSecret(value) then return nil, "secret" end; if value == nil then return 0, "readable" end; return tonumber(value) or 0, "readable" end
local function confirmPendingMarkerAttempt(serial)
  local pending = pendingMarkerAttempt; if not pending or (serial and pending.serial ~= serial) then return nil, "marker-attempt-stale" end
  local now = monotonicTime(); if pending.expiresAt > 0 and now > 0 and now > pending.expiresAt then pendingMarkerAttempt = nil; setResult("failed", "marker-attempt-expired", pending.marker, pending.source); refreshRuntimeFrameIfOpen(); return nil, "marker-attempt-expired" end
  local identity, identityError = getRuntimeInstructionIdentity(); if not identity then pendingMarkerAttempt = nil; setResult("failed", identityError, pending.marker, pending.source); refreshRuntimeFrameIfOpen(); return nil, identityError end
  if tostring(identity.assignmentID or "") ~= tostring(pending.assignmentID or "") or tonumber(identity.marker) ~= tonumber(pending.marker) then pendingMarkerAttempt = nil; setResult("failed", "assignment-mismatch", pending.marker, pending.source); refreshRuntimeFrameIfOpen(); return nil, "assignment-mismatch" end
  local observedMarker, readState = readObservedMarker(pending.unitToken); if readState == "readable" and observedMarker ~= tonumber(pending.marker) then return nil, observedMarker == 0 and "marker-event-without-expected-icon" or "marker-event-wrong-icon" end
  pendingMarkerAttempt = nil; local advanced, advanceError = notifyMarkerConfirmed(pending.marker, pending.assignmentID); if not advanced then setResult("failed", advanceError or "runtime-not-advanced", pending.marker, pending.source); refreshRuntimeFrameIfOpen(); return nil, advanceError or "runtime-not-advanced" end
  local resultCode = readState == "readable" and "marker-confirmed-readback" or "marker-confirmed-event"; setResult("confirmed", resultCode, pending.marker, pending.source); local refreshDelay = recordSubmissionAndGetRefreshDelay(); scheduleInstructionRefresh(refreshDelay > 0 and "marker-rate-paced" or "marker-confirmed", refreshDelay); refreshRuntimeFrameIfOpen(); return true, refreshDelay > 0 and "confirmed-rate-paced" or resultCode
end
local function submitLegacyDirectTarget(expectedAssignmentID, source)
  source = source or "legacy-actionbar-macro"; local identity, identityError = getRuntimeInstructionIdentity(); if not identity then setResult("failed", identityError, nil, source); refreshRuntimeFrameIfOpen(); return nil, identityError end
  if tostring(expectedAssignmentID or "") ~= tostring(identity.assignmentID or "") then setResult("failed", "assignment-mismatch", identity.marker, source); refreshRuntimeFrameIfOpen(); return nil, "assignment-mismatch" end
  local unitToken = identity.requiresMouseover and "mouseover" or "target"; local observedMarker, readState = readObservedMarker(unitToken); configureCurrentInstruction("legacy-markdone-migrated")
  if readState ~= "readable" or observedMarker ~= tonumber(identity.marker) then setResult("failed", "legacy-macro-unverified", identity.marker, source); refreshRuntimeFrameIfOpen(); return nil, "legacy-macro-unverified" end
  local advanced, advanceError = notifyMarkerConfirmed(identity.marker, identity.assignmentID); if not advanced then setResult("failed", advanceError or "runtime-not-advanced", identity.marker, source); refreshRuntimeFrameIfOpen(); return nil, advanceError or "runtime-not-advanced" end
  setResult("confirmed", "legacy-marker-confirmed-readback", identity.marker, source); local refreshDelay = recordSubmissionAndGetRefreshDelay(); scheduleInstructionRefresh(refreshDelay > 0 and "marker-rate-paced" or "legacy-marker-confirmed", refreshDelay); refreshRuntimeFrameIfOpen(); return true, "legacy-marker-confirmed-readback"
end
local function validateBulkAnchors(expectedToken, source) source = source or "legacy-bulk-anchor"; setResult("failed", "legacy-bulk-validation-disabled", nil, source); return nil, "legacy-bulk-validation-disabled" end
local function validateBulkStep(encodedStep, source) source = source or "legacy-bulk-step"; setResult("failed", "legacy-bulk-validation-disabled", nil, source); return nil, "legacy-bulk-validation-disabled" end
local function currentBulkToken(batchIndex) local identities = getRuntimeBulkIdentities(batchIndex); if not identities then return nil end; return bulkTokenForIdentities(identities) end
local function currentSubmissionBucket(create, explicitPullIndex) local runtimeState = Addon.RuntimeController and Addon.RuntimeController:GetState() or nil; local pullIndex = tonumber(explicitPullIndex) or (runtimeState and tonumber(runtimeState.currentPullIndex) or nil); if not pullIndex then return nil, nil end; if create and type(submittedBulkTokens[pullIndex]) ~= "table" then submittedBulkTokens[pullIndex] = {} end; return submittedBulkTokens[pullIndex], pullIndex end
local function tokenForPullBatch(pullIndex, batchIndex) pullIndex, batchIndex = tonumber(pullIndex), tonumber(batchIndex); if not pullIndex or not batchIndex then return nil end; if routeBindingActive() and Addon.RuntimeController and type(Addon.RuntimeController.GetRouteMacroDescriptor) == "function" then local descriptor = Addon.RuntimeController:GetRouteMacroDescriptor(pullIndex, batchIndex); return descriptor and descriptor.token or nil end; local runtimeState = Addon.RuntimeController and Addon.RuntimeController:GetState() or nil; if runtimeState and tonumber(runtimeState.currentPullIndex) == pullIndex then return currentBulkToken(batchIndex) end end
local function submissionStateForPull(pullIndex)
  pullIndex = tonumber(pullIndex); if not pullIndex then return nil, "pull-unavailable" end; local bucket = currentSubmissionBucket(false, pullIndex) or {}; local tokens, submitted = {}, {}
  for batchIndex = 1, MAX_ROUTE_BATCHES do tokens[batchIndex] = tokenForPullBatch(pullIndex, batchIndex); submitted[batchIndex] = tokens[batchIndex] ~= nil and bucket[batchIndex] == tokens[batchIndex] or false end
  if not tokens[1] then return nil, "instruction-unavailable" end; local allSubmitted = true; for batchIndex = 1, MAX_ROUTE_BATCHES do if tokens[batchIndex] and not submitted[batchIndex] then allSubmitted = false; break end end
  return { pullIndex = pullIndex, tokens = tokens, submitted = submitted, allSubmitted = allSubmitted, firstToken = tokens[1], secondToken = tokens[2], thirdToken = tokens[3], firstSubmitted = submitted[1] == true, secondSubmitted = tokens[2] == nil or submitted[2] == true, thirdSubmitted = tokens[3] == nil or submitted[3] == true }
end
local function requiredBulkSubmissionState() local runtimeState = Addon.RuntimeController and Addon.RuntimeController:GetState() or nil; local pullIndex = runtimeState and tonumber(runtimeState.currentPullIndex) or nil; if not pullIndex then return nil, "pull-unavailable" end; return submissionStateForPull(pullIndex) end
local function clearPullSubmissionState(pullIndex, reason) pullIndex = tonumber(pullIndex); if not pullIndex then return end; submittedBulkTokens[pullIndex] = nil; pendingPullAdvances[pullIndex] = nil; if pendingPullAdvance and tonumber(pendingPullAdvance.pullIndex) == pullIndex then pendingPullAdvance = nil end; if reason then log("DEBUG", "Pull submission state reset for pull "..tostring(pullIndex)..": "..tostring(reason), false) end end
local function resetBulkSubmissionState(reason) submittedBulkTokens = {}; pendingPullAdvance = nil; pendingPullAdvances = {}; if reason then log("DEBUG", "Bulk submission state reset: "..tostring(reason), false) end end
local function shouldResetBulkSubmissionState(reason) reason = tostring(reason or ""); return reason == "dungeon-run-start" or reason == "route-changed" or reason == "marker-plan-changed" or (reason == "pull-changed" and not routeBindingActive()) or (reason == "pull-completed" and not routeBindingActive()) or reason == "run-progress-reset" end

local function confirmBulkSubmission(expectedToken, source)
  source = source or "actionbar-bulk-macro"
  if type(InCombatLockdown) ~= "function" or not InCombatLockdown() then setResult("failed", "bulk-requires-combat", nil, source); log("WARN", "Use the marker macro after the pull has entered combat.", true); refreshRuntimeFrameIfOpen(); return nil, "bulk-requires-combat" end
  local descriptor; local batchIndex
  if routeBindingActive() then
    if not Addon.RuntimeController or type(Addon.RuntimeController.ResolveRouteMacroToken) ~= "function" then setResult("failed", "route-macro-runtime-unavailable", nil, source); return nil, "route-macro-runtime-unavailable" end
    local descriptorError; descriptor, descriptorError = Addon.RuntimeController:ResolveRouteMacroToken(expectedToken); if not descriptor then setResult("failed", descriptorError or "route-macro-token-unavailable", nil, source); return nil, descriptorError or "route-macro-token-unavailable" end
    batchIndex = tonumber(descriptor.batchIndex) or 1; local executionAllowed, gateError = routeMacroExecutionAllowed(); if not executionAllowed then setResult("failed", gateError or "route-macro-execution-blocked", nil, source); return nil, gateError or "route-macro-execution-blocked" end
    local runtimeState = Addon.RuntimeController:GetState(); if routePullAlreadyCompleted(runtimeState, descriptor.pullIndex) then setResult("failed", "pull-completed", nil, source); return nil, "pull-completed" end
    if tonumber(runtimeState and runtimeState.currentPullIndex) ~= tonumber(descriptor.pullIndex) then local switched, switchError = Addon.RuntimeController:SetPullByIndex(descriptor.pullIndex, "route-macro"); if not switched then setResult("failed", switchError or "route-macro-pull-switch-failed", nil, source); return nil, switchError or "route-macro-pull-switch-failed" end end
    if Addon.PullDeathTracker and type(Addon.PullDeathTracker.ActivatePull) == "function" then local activated, activateError = Addon.PullDeathTracker:ActivatePull(descriptor.pullIndex, "route-macro-submitted"); if not activated then setResult("failed", activateError or "pull-death-context-unavailable", nil, source); return nil, activateError or "pull-death-context-unavailable" end end
  else local _, parsedBatchIndex = parseBulkToken(expectedToken); batchIndex = parsedBatchIndex or 1 end
  local identities, bulkError = getRuntimeBulkIdentities(batchIndex); if not identities then setResult("failed", bulkError, nil, source); return nil, bulkError end
  local actualToken = bulkTokenForIdentities(identities); if tostring(expectedToken or "") ~= tostring(actualToken or "") then setResult("failed", "bulk-token-mismatch", identities[1] and identities[1].marker, source); return nil, "bulk-token-mismatch" end
  local now = monotonicTime(); local previousAttemptAt = lastBulkSubmissionAt; if now > 0 then lastBulkSubmissionAt = now end
  if previousAttemptAt > 0 and now > 0 then local remaining = (previousAttemptAt + MARKER_WINDOW_SECONDS) - now; if remaining > 0 then setResult("failed", "bulk-marker-throttle-window", identities[1] and identities[1].marker, source); local retryName = descriptor and descriptor.name or ("MDTPM"..tostring(batchIndex)); log("WARN", ("Too soon. Wait about %d sec from now, then press %s again."):format(MARKER_WINDOW_SECONDS, retryName), true); refreshRuntimeFrameIfOpen(); return nil, "bulk-marker-throttle-window" end end
  local bucket, pullIndex = currentSubmissionBucket(true, descriptor and descriptor.pullIndex or nil); if not bucket then return nil, "pull-unavailable" end
  if bucket[batchIndex] == actualToken then setResult("submitted", "bulk-batch-already-submitted", identities[1] and identities[1].marker, source); refreshRuntimeFrameIfOpen(); return true, 0 end
  bucket[batchIndex] = actualToken; local _, submitStateError = Addon.RuntimeController:OnBatchSubmitted(identities); if submitStateError and submitStateError ~= "batch-submitted" then log("DEBUG", "Marker-pool submission state not updated: "..tostring(submitStateError), false) end
  local submission = requiredBulkSubmissionState(); if submission and submission.allSubmitted then local runtimeState = Addon.RuntimeController:GetState(); local pending = { pullIndex = pullIndex or runtimeState.currentPullIndex, routeFingerprint = runtimeState.routeFingerprint, armedAt = now, reason = "all-required-batches-submitted" }; pendingPullAdvance = pending; if routeBindingActive() then pendingPullAdvances[pending.pullIndex] = pending end end
  setResult("submitted", "bulk-macro-submitted", identities[#identities] and identities[#identities].marker, source); refreshRuntimeFrameIfOpen(); return true, #identities
end
local function verifyPlayerAliveAfterCombat() if type(UnitIsDeadOrGhost) ~= "function" then return nil, "player-state-unavailable" end; local stateOK, dead = pcall(UnitIsDeadOrGhost, "player"); if not stateOK or isSecret(dead) or type(dead) ~= "boolean" then return nil, "player-state-unverified" end; if dead then return nil, "player-dead-or-ghost" end; return true end
local function finalizeBoundRoutePullsAfterCombat()
  local alive, aliveError = verifyPlayerAliveAfterCombat(); if not alive then resetBulkSubmissionState(aliveError); return false, aliveError end
  local runtimeState = Addon.RuntimeController:GetState(); local routeFingerprint = tostring(runtimeState.routeFingerprint or ""); local pendingIndexes = {}
  for pullIndex, pending in pairs(pendingPullAdvances) do if type(pending) == "table" and tostring(pending.routeFingerprint or "") == routeFingerprint then pendingIndexes[#pendingIndexes + 1] = tonumber(pullIndex) end end; table.sort(pendingIndexes); if #pendingIndexes == 0 then return false, "pull-advance-not-armed" end
  local completedCount = 0; local blocked = {}
  for _, pullIndex in ipairs(pendingIndexes) do
    local submission, submissionError = submissionStateForPull(pullIndex)
    if not submission or not submission.allSubmitted then blocked[pullIndex] = submissionError or "bulk-batches-incomplete"; clearPullSubmissionState(pullIndex, blocked[pullIndex])
    else
      local deathVerdict, deathReason = Addon.PullDeathTracker:GetCompletionVerdict(pullIndex)
      if deathVerdict ~= true then blocked[pullIndex] = deathReason or "pull-deaths-unproven"; clearPullSubmissionState(pullIndex, blocked[pullIndex]); if Addon.PullDeathTracker and type(Addon.PullDeathTracker.RetirePull) == "function" then Addon.PullDeathTracker:RetirePull(pullIndex, blocked[pullIndex]) end
      else local completed, completeError = Addon.RuntimeController:CompletePullByIndex(pullIndex, { silent = true }); if not completed then blocked[pullIndex] = completeError or "pull-complete-failed" else completedCount = completedCount + 1; clearPullSubmissionState(pullIndex, "combat-ended-pull-finalized") end end
    end
  end
  pendingPullAdvance = nil; local after = Addon.RuntimeController:GetState(); if after.completed and tonumber(after.currentPullPosition) < tonumber(after.pullCount) then Addon.RuntimeController:SetPullByPosition(after.currentPullPosition + 1, "combat-auto-advance") else Addon.MarkerExecutor:OnInstructionChanged(completedCount > 0 and "pull-completed" or "combat-ended-overlap-unresolved") end
  if completedCount > 0 then return true, next(blocked) and "some-overlap-pulls-unresolved" or nil end; local currentReason = blocked[tonumber(after.currentPullIndex)]; if currentReason then return false, currentReason end; for _, reason in pairs(blocked) do return false, reason end; return false, "bulk-batches-incomplete"
end
local function finalizeSubmittedPullAfterCombat()
  if routeBindingActive() then return finalizeBoundRoutePullsAfterCombat() end
  local alive, aliveError = verifyPlayerAliveAfterCombat(); if not alive then resetBulkSubmissionState(aliveError); return false, aliveError end
  local submission, submissionError = requiredBulkSubmissionState(); if not submission then return false, submissionError end; if not submission.allSubmitted then return false, "bulk-batches-incomplete" end; if not pendingPullAdvance then return false, "pull-advance-not-armed" end
  local runtimeState = Addon.RuntimeController:GetState(); if tonumber(runtimeState.currentPullIndex) ~= tonumber(pendingPullAdvance.pullIndex) or tostring(runtimeState.routeFingerprint or "") ~= tostring(pendingPullAdvance.routeFingerprint or "") then resetBulkSubmissionState("pull-advance-context-changed"); return false, "pull-advance-context-changed" end
  local deathVerdict, deathReason = Addon.PullDeathTracker:GetCompletionVerdict(runtimeState.currentPullIndex); if deathVerdict ~= true then resetBulkSubmissionState("pull-deaths-unproven"); return false, deathReason or "pull-deaths-unproven" end
  local completed, completeError = Addon.RuntimeController:CompleteCurrentPull(true); if not completed then return false, completeError or "pull-complete-failed" end; resetBulkSubmissionState("combat-ended-pull-finalized"); return true
end

function Executor:Initialize() createSmartSecureButton(); applySecureConfiguration("addon-loaded"); refreshSmartMacros("addon-loaded", nil, false); return true end
function Executor:ArmDirectTarget(expectedAssignmentID, source) return armDirectTarget(expectedAssignmentID, source or "actionbar-macro") end
function Executor:ConfirmDirectTarget(expectedAssignmentID, source) return submitLegacyDirectTarget(expectedAssignmentID, source or "legacy-actionbar-macro") end
function Executor:ValidateBulkAnchors(expectedToken, source) return validateBulkAnchors(expectedToken, source or "actionbar-bulk-anchor") end
function Executor:ValidateBulkStep(encodedStep, source) return validateBulkStep(encodedStep, source or "actionbar-bulk-step") end
function Executor:ConfirmBulk(expectedToken, source) return confirmBulkSubmission(expectedToken, source or "actionbar-bulk-macro") end
function Executor:OnPullDeathProgress(reason)
  local death = Addon.PullDeathTracker:GetState(); if routeBindingActive() then for pullIndex, pending in pairs(pendingPullAdvances) do local pullDeath = Addon.PullDeathTracker:GetState(pullIndex); if pullDeath and pullDeath.complete == true then pending.deathComplete = true; pending.reason = "all-required-batches-submitted-deaths-observed" end end elseif pendingPullAdvance and death and death.complete == true then pendingPullAdvance.deathComplete = true; pendingPullAdvance.reason = "all-required-batches-submitted-deaths-observed" end
  refreshRuntimeFrameIfOpen(); return death, reason
end
function Executor:OnRaidTargetUpdate() local pending = pendingMarkerAttempt; if not pending then return false, "no-marker-attempt" end; local serial = pending.serial; local confirmed, confirmationError = confirmPendingMarkerAttempt(serial); if not confirmed and confirmationError ~= "marker-event-without-expected-icon" and confirmationError ~= "marker-event-wrong-icon" then log("DEBUG", "Marker update was not accepted: "..tostring(confirmationError), false) end; return confirmed == true, confirmationError end
function Executor:InvalidateExecution(reason)
  executionInvalidated = true
  executionInvalidationReason = tostring(reason or "execution-invalidated")
  cancelPendingMarkerAttempt()
  instructionRefreshSerial = instructionRefreshSerial + 1
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    pendingSecureRefresh = true
    smartMacroManager:MarkPending()
    return false, "in-combat"
  end
  if smartButton then
    smartButton:SetAttribute("type1", "macro")
    smartButton:SetAttribute("macrotext1", SAFE_IDLE_MACRO)
  end
  local parked, parkError = smartMacroManager:ParkAllManagedExecution(executionInvalidationReason)
  if not parked and parkError ~= "macro-api-unavailable" and parkError ~= "edit-macro-unavailable" then
    log("WARN", "Managed execution could not be fully parked: "..tostring(parkError), false)
  end
  refreshRuntimeFrameIfOpen()
  return parked ~= false, parkError
end

function Executor:OnRuntimeValidated(reason)
  executionInvalidated = false
  executionInvalidationReason = nil
  return self:OnInstructionChanged(reason or "runtime-validated")
end

function Executor:OnInstructionChanged(reason)
  if shouldResetBulkSubmissionState(reason) then resetBulkSubmissionState(reason) end; cancelPendingMarkerAttempt(); instructionRefreshSerial = instructionRefreshSerial + 1
  if type(InCombatLockdown) == "function" and InCombatLockdown() then pendingSecureRefresh = true; smartMacroManager:MarkPending(); return false, "in-combat" end
  local remaining = rateDelayRemaining(); if remaining > 0 then scheduleInstructionRefresh(reason or "instruction-changed", remaining); return false, "marker-rate-paced" end
  return configureCurrentInstruction(reason or "instruction-changed")
end
function Executor:OnMacroListChanged()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then smartMacroManager:MarkPending(); return false, "in-combat" end
  if macroListRefreshScheduled then return true, "scheduled" end; macroListRefreshScheduled = true
  local function run() macroListRefreshScheduled = false; local results, refreshError = configureCurrentInstruction("macro-list-changed"); if not results and refreshError ~= "in-combat" and refreshError ~= "macro-api-unavailable" then log("WARN", "Managed macro self-heal failed: "..tostring(refreshError), false) end; refreshRuntimeFrameIfOpen() end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0, run) else run() end; return true, "scheduled"
end
function Executor:OnCVarUpdate(cvarName) if tostring(cvarName or ""):lower() ~= "actionbuttonusekeydown" then return false end; local clickType, clickError = configureSmartButtonClicks(); if clickType then log("DEBUG", "Secure marker click mode changed to "..clickType..".", false) elseif clickError ~= "in-combat" then log("WARN", "Secure click mode could not be refreshed: "..tostring(clickError), false) end; return clickType, clickError end
function Executor:OnCombatEnded()
  cancelPendingMarkerAttempt(); instructionRefreshSerial = instructionRefreshSerial + 1; configureSmartButtonClicks(); local finalized, finalizeError = finalizeSubmittedPullAfterCombat(); if Addon.PullDeathTracker and type(Addon.PullDeathTracker.OnCombatEnded) == "function" then Addon.PullDeathTracker:OnCombatEnded() end
  if not finalized and finalizeError ~= "bulk-batches-incomplete" and finalizeError ~= "instruction-unavailable" and finalizeError ~= "outside-dungeon" and finalizeError ~= "route-instance-unverified" and finalizeError ~= "route-instance-mismatch" and finalizeError ~= "pull-completed" and finalizeError ~= "death-incomplete" and finalizeError ~= "some-overlap-pulls-unresolved" then log("WARN", "Pull was not advanced after combat: "..tostring(finalizeError), false) end
  local remaining = rateDelayRemaining(); if remaining > 0 then scheduleInstructionRefresh("combat-ended", remaining) end; local applied, applyError = applySecureConfiguration("combat-ended"); local macroApplied, macroError = configureCurrentInstruction("combat-ended"); if not applied and applyError ~= "button-unavailable" then log("WARN", "Safe marker state could not be restored after combat: "..tostring(applyError), false) end; if not macroApplied and macroError ~= "macro-api-unavailable" and macroError ~= "in-combat" then log("WARN", "Macro refresh after combat: "..tostring(macroError), false) end; refreshRuntimeFrameIfOpen(); return applied, applyError or macroError
end
function Executor:ApplySecureConfiguration(reason) return applySecureConfiguration(reason) end
function Executor:EnsureSmartMacros(pickupIndex) if routeBindingActive() then local descriptor; local pullIndex = Addon.RuntimeController and Addon.RuntimeController:GetState().currentPullIndex or nil; if pullIndex and tonumber(pickupIndex) then descriptor = Addon.RuntimeController:GetRouteMacroDescriptor(pullIndex, tonumber(pickupIndex)) end; return refreshRouteMacros("ui", descriptor and descriptor.name or nil, true) end; return refreshSmartMacros("ui", tonumber(pickupIndex) or nil, true) end
function Executor:EnsureRouteMacros(pickupPullIndex, pickupBatchIndex) local pickupName; if pickupPullIndex and pickupBatchIndex and Addon.RuntimeController and type(Addon.RuntimeController.GetRouteMacroDescriptor) == "function" then local descriptor = Addon.RuntimeController:GetRouteMacroDescriptor(pickupPullIndex, pickupBatchIndex); pickupName = descriptor and descriptor.name or nil end; return refreshRouteMacros("ui-route", pickupName, true) end
function Executor:RefreshRouteMacros(reason) return refreshRouteMacros(reason or "route-refresh", nil, true) end
function Executor:ParkRouteMacros(reason) return smartMacroManager:ParkRecognizedRouteMacros(reason or "route-park") end
function Executor:RetireRouteMacros(reason) return smartMacroManager:RetireRecognizedRouteMacros(reason or "route-unbound") end
function Executor:GetRouteMacroStatus() return getRouteMacroStatus() end
function Executor:RefreshSmartMacro(reason) return refreshSmartMacro(reason, false, false) end
function Executor:RefreshSmartMacros(reason) return refreshSmartMacros(reason, nil, false) end
function Executor:GetSmartMacroStatus(batchIndex) batchIndex = tonumber(batchIndex) or 1; return getSmartMacroStatus(SMART_MACRO_NAMES[batchIndex], batchIndex) end
function Executor:GetState()
  local identity, identityError = getRuntimeInstructionIdentity(); local batch, batchError = getRuntimeBulkIdentities(1); local secondBatch, secondBatchError = getRuntimeBulkIdentities(2); local smartMacro1 = getSmartMacroStatus(SMART_MACRO_NAME, 1); local smartMacro2 = getSmartMacroStatus(SECOND_SMART_MACRO_NAME, 2); local routeMacroStatus = getRouteMacroStatus()
  return { markerCount = 8, executionMode = "dual-three-target-exact-name-owner-elected", combatMarking = true, bulkLimit = BULK_MARKER_LIMIT, currentBatch = batch, currentBatchError = batchError, secondBatch = secondBatch, secondBatchError = secondBatchError, phase = "direct", currentInstruction = (batch and batch[1]) or identity, currentInstructionError = batchError or identityError, pendingSecureRefresh = pendingSecureRefresh, executionInvalidated = executionInvalidated, executionInvalidationReason = executionInvalidationReason, pendingMacroRefresh = smartMacroManager:IsPending(), lastMarkerConfirmation = lastResult,
    pendingMarkerConfirmation = pendingMarkerAttempt and { assignmentID = pendingMarkerAttempt.assignmentID, marker = pendingMarkerAttempt.marker, source = pendingMarkerAttempt.source, armedAt = pendingMarkerAttempt.armedAt, expiresAt = pendingMarkerAttempt.expiresAt } or nil,
    nextMarkerReadyAt = nextInstructionReadyAt > 0 and nextInstructionReadyAt or nil, markerRateWindowSeconds = MARKER_WINDOW_SECONDS, markerRateWindowLimit = MAX_DISTINCT_MARKS_PER_WINDOW, markerConfirmTimeoutSeconds = MARKER_CONFIRM_TIMEOUT_SECONDS, markerOwnership = Addon.MarkerOwnership:GetState(),
    pendingPullAdvance = pendingPullAdvance and { pullIndex = pendingPullAdvance.pullIndex, routeFingerprint = pendingPullAdvance.routeFingerprint, armedAt = pendingPullAdvance.armedAt, reason = pendingPullAdvance.reason, deathComplete = pendingPullAdvance.deathComplete == true } or nil,
    pendingPullAdvances = (function() local result = {}; for pullIndex, pending in pairs(pendingPullAdvances) do result[#result + 1] = { pullIndex = tonumber(pullIndex), routeFingerprint = pending.routeFingerprint, armedAt = pending.armedAt, reason = pending.reason, deathComplete = pending.deathComplete == true } end; table.sort(result, function(left, right) return tonumber(left.pullIndex) < tonumber(right.pullIndex) end); return result end)(),
    progressionMode = routeBindingActive() and "overlap-aware-death-gated-safe-boundary" or "death-gated-safe-boundary", pullDeathTracking = Addon.PullDeathTracker:GetState(),
    bulkSubmission = (function() local current = requiredBulkSubmissionState(); return current and { batch1 = current.firstSubmitted == true, batch2Required = current.secondToken ~= nil, batch2 = current.secondSubmitted == true, batch3Required = current.thirdToken ~= nil, batch3 = current.thirdSubmitted == true, allRequired = current.allSubmitted == true } or nil end)(),
    keybindCommand = "CLICK "..SMART_BUTTON_NAME..":LeftButton", smartMacro = smartMacro1, smartMacros = { smartMacro1, smartMacro2 }, routeMacroMode = routeBindingActive(), routeMacros = routeMacroStatus, secureClickType = actionUsesKeyDown() and "AnyDown" or "AnyUp" }
end
