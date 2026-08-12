local _, Addon = ...

local MarkerPlanner = {}
Addon.MarkerPlanner = MarkerPlanner

local DataUtils = Addon.DataUtils
local MAX_ASSIGNMENTS = 2000
local MAX_TARGET_NAME_BYTES = 120
local MAX_EXECUTABLE_ASSIGNMENTS_PER_PULL = 8
local MAX_ASSIGNMENTS_PER_BATCH = 3
local MAX_BATCHES_PER_PULL = 3

local MARKER_FALLBACK_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
local MARKER_PRIORITY = {}
for priority, marker in ipairs(MARKER_FALLBACK_ORDER) do MARKER_PRIORITY[marker] = priority end

local function markerPriority(marker)
  return MARKER_PRIORITY[tonumber(marker)] or 99
end

local function finding(findings, severity, code, path, details)
  local item = { severity = severity, code = code, path = path }
  if details then item.details = details end
  findings[#findings + 1] = item
end

local function assignmentKey(enemyIndex, cloneIndex)
  return ("e%d:c%d"):format(enemyIndex, cloneIndex)
end

local function safeTargetName(value)
  if DataUtils.IsSecret(value) or type(value) ~= "string" then return nil, "assignment-target-name-unavailable" end
  local name = DataUtils.Trim(value)
  if not name or name == "" then return nil, "assignment-target-name-unavailable" end
  if #name > MAX_TARGET_NAME_BYTES then return nil, "target-name-too-long" end
  if name:find("[%c%[%];]") then return nil, "unsafe-target-name" end
  return name
end

local function buildAssignment(enemy, clone, marker, routeOrder, sourceNamesVerified)
  local enemyIndex = DataUtils.PositiveInteger(enemy and enemy.enemyIndex)
  local cloneIndex = DataUtils.PositiveInteger(clone and clone.cloneIndex)
  marker = DataUtils.PositiveInteger(marker, 8)
  if not enemyIndex then return nil, "invalid-enemy-index" end
  if not cloneIndex then return nil, "invalid-clone-index" end
  if not marker then return nil, "invalid-marker" end

  local npcID = DataUtils.PositiveInteger(enemy and enemy.npcID)
  local targetName, targetNameError = safeTargetName(enemy and enemy.name)
  local targetNameResolution = sourceNamesVerified and "source-client-locale" or "source-unverified"
  local targetNameVerified = sourceNamesVerified == true
  if npcID and Addon.CreatureNameResolver and type(Addon.CreatureNameResolver.Resolve) == "function" then
    local resolved, resolution, verified = Addon.CreatureNameResolver:Resolve(npcID, targetName)
    if resolved then
      targetName, targetNameError = safeTargetName(resolved)
      targetNameResolution = resolution or targetNameResolution
      targetNameVerified = verified == true or targetNameVerified
    end
  end
  return {
    id = assignmentKey(enemyIndex, cloneIndex),
    enemyIndex = enemyIndex,
    cloneIndex = cloneIndex,
    npcID = npcID,
    name = targetName,
    targetName = targetName,
    targetNameError = targetNameError,
    targetNameResolution = targetNameResolution,
    targetNameVerified = targetNameVerified,
    requestedMarker = marker,
    marker = marker,
    priority = markerPriority(marker),
    routeOrder = DataUtils.PositiveInteger(routeOrder, MAX_ASSIGNMENTS) or 1,
    method = "exact-name-macro",
    executionMethod = "exact-name",
    enabled = true,
    markerRemapped = false,
    useSetUnmarked = true,
  }
end

local function assignmentSort(left, right)
  if left.routeOrder ~= right.routeOrder then return left.routeOrder < right.routeOrder end
  if left.priority ~= right.priority then return left.priority < right.priority end
  if left.enemyIndex ~= right.enemyIndex then return left.enemyIndex < right.enemyIndex end
  return left.cloneIndex < right.cloneIndex
end

local function buildIdentityTotals(snapshotPull)
  local totals = {}
  for _, enemy in ipairs(snapshotPull.enemies or {}) do
    local identity = enemy.npcID and ("npc:"..enemy.npcID) or ("enemy:"..tostring(enemy.enemyIndex))
    totals[identity] = (totals[identity] or 0) + #(enemy.clones or {})
  end
  return totals
end

local function buildRouteNameTotals(snapshot)
  local totals = {}
  for _, pull in ipairs(snapshot.pulls or {}) do
    for _, enemy in ipairs(pull.enemies or {}) do
      local exactName = type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
      if exactName and exactName ~= "" then totals[exactName] = (totals[exactName] or 0) + #(enemy.clones or {}) end
    end
  end
  return totals
end

local function buildPullNameTotals(snapshotPull)
  local totals = {}
  for _, enemy in ipairs(snapshotPull.enemies or {}) do
    local exactName = type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
    if exactName and exactName ~= "" then totals[exactName] = (totals[exactName] or 0) + #(enemy.clones or {}) end
  end
  return totals
end

local function buildResolvedPullNameTotals(snapshotPull, sourceNamesVerified)
  local totals = {}
  for _, enemy in ipairs(snapshotPull.enemies or {}) do
    local count = #(enemy.clones or {})
    if count > 0 then
      local sourceName = type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
      local resolvedName = sourceName
      local npcID = DataUtils.PositiveInteger(enemy.npcID)
      if npcID and Addon.CreatureNameResolver and type(Addon.CreatureNameResolver.Resolve) == "function" then
        local resolved = Addon.CreatureNameResolver:Resolve(npcID, sourceName)
        if resolved then resolvedName = resolved end
      elseif not sourceNamesVerified then
        resolvedName = nil
      end
      local safeName = safeTargetName(resolvedName)
      if safeName then totals[safeName] = (totals[safeName] or 0) + count end
    end
  end
  return totals
end

local function buildResolvedRouteNameTotals(snapshot, sourceNamesVerified)
  local totals = {}
  for _, pull in ipairs(snapshot.pulls or {}) do
    for name, count in pairs(buildResolvedPullNameTotals(pull, sourceNamesVerified)) do
      totals[name] = (totals[name] or 0) + count
    end
  end
  return totals
end

local function buildMarkedNameTotals(snapshotPull)
  local totals = {}
  for _, enemy in ipairs(snapshotPull.enemies or {}) do
    local exactName = type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
    if exactName and exactName ~= "" then
      for _, clone in ipairs(enemy.clones or {}) do
        if DataUtils.PositiveInteger(clone.marker, 8) then totals[exactName] = (totals[exactName] or 0) + 1 end
      end
    end
  end
  return totals
end

local function buildDeathTracking(snapshotPull)
  local byNPC = {}
  local total = 0
  local available = true
  for _, enemy in ipairs(snapshotPull.enemies or {}) do
    local count = #(enemy.clones or {})
    if count > 0 then
      total = total + count
      local npcID = DataUtils.PositiveInteger(enemy.npcID)
      if npcID then
        byNPC[npcID] = (byNPC[npcID] or 0) + count
      else
        available = false
      end
    end
  end
  if total == 0 then available = false end
  return {
    available = available,
    expectedTotal = total,
    expectedByNPC = byNPC,
    mode = available and "npc-death-advisory" or "combat-boundary",
  }
end

local function reserveExactMarkers(assignments, findings, path)
  local usage = {}
  for _, assignment in ipairs(assignments) do
    local marker = tonumber(assignment.marker)
    if usage[marker] then
      finding(findings, "error", "duplicate-marker-in-pull", path, {
        marker = marker,
        firstAssignmentID = usage[marker],
        secondAssignmentID = assignment.id,
        policy = "mdt-marker-is-authoritative-no-remap",
      })
      return nil, "duplicate-marker-in-pull"
    end
    usage[marker] = assignment.id or true
  end
  return usage
end

local function classifyTargeting(assignments, findings, path)
  local byName = {}
  for _, assignment in ipairs(assignments) do
    local name = assignment.targetName
    if name then
      byName[name] = byName[name] or {}
      byName[name][#byName[name] + 1] = assignment
    end
  end

  local automatic = true
  for name, group in pairs(byName) do
    local pullNameTotal = 0
    local adjacentPullNameTotal = 0
    local otherPullNameTotal = 0
    local dungeonNameTotal = 0
    for _, assignment in ipairs(group) do
      pullNameTotal = math.max(pullNameTotal, tonumber(assignment.pullNameTotal) or 0)
      adjacentPullNameTotal = math.max(adjacentPullNameTotal, tonumber(assignment.adjacentPullNameTotal) or 0)
      otherPullNameTotal = math.max(otherPullNameTotal, tonumber(assignment.otherPullNameTotal) or 0)
      dungeonNameTotal = math.max(dungeonNameTotal, tonumber(assignment.dungeonNameTotal) or 0)
    end
    if #group > 1 or pullNameTotal > 1 or otherPullNameTotal > 0 or dungeonNameTotal > 1 then
      automatic = false
      table.sort(group, assignmentSort)
      for ordinal, assignment in ipairs(group) do
        assignment.sameNameSequence = true
        assignment.duplicateGroupName = name
        assignment.duplicateNameOrdinal = ordinal
        assignment.markedNameTotal = math.max(#group, tonumber(assignment.markedNameTotal) or 0)
        assignment.executionMethod = "same-name-manual"
        assignment.method = "same-name-secure-limit"
        assignment.matchPolicy = dungeonNameTotal > 1
          and "dungeon-wide-same-name-unit-identity-unavailable"
          or (otherPullNameTotal > 0 and "route-wide-same-name-unit-identity-unavailable" or "same-name-unit-identity-unavailable")
        assignment.automaticTargeting = false
      end
      finding(findings, "warning", "same-name-automatic-targeting-unavailable", path, {
        targetName = name,
        markedCount = #group,
        pullCount = pullNameTotal,
        adjacentPullCount = adjacentPullNameTotal,
        otherPullCount = otherPullNameTotal,
        dungeonCount = dungeonNameTotal,
        policy = dungeonNameTotal > 1
          and "fail-closed-dungeon-wide-exact-name-ambiguity"
          or (otherPullNameTotal > 0 and "fail-closed-route-wide-skip-chain-pull-name-ambiguity" or "fail-closed-no-unfiltered-target-cycle"),
      })
    end
  end

  for _, assignment in ipairs(assignments) do
    if not assignment.sameNameSequence then
      assignment.executionMethod = "exact-name"
      assignment.method = "exact-name-macro"
      assignment.matchPolicy = "exact-name"
      assignment.automaticTargeting = true
      assignment.duplicateNameOrdinal = 1
    end
  end
  return automatic
end

local function batchMacroLength(assignments, batchIndex, pullIndex, routeFingerprint)
  if type(assignments) ~= "table" or #assignments == 0 then return 0 end
  if not Addon.MarkerMacro or type(Addon.MarkerMacro.BuildBulkBody) ~= "function" then
    return nil, "marker-macro-builder-unavailable"
  end
  local identities = {}
  for _, assignment in ipairs(assignments) do
    identities[#identities + 1] = {
      assignmentID = assignment.id,
      marker = assignment.marker,
      targetName = assignment.targetName,
      executionMethod = assignment.executionMethod,
      pullIndex = pullIndex,
      routeFingerprint = routeFingerprint,
      batchIndex = batchIndex,
    }
  end
  local body, buildError, bytes = Addon.MarkerMacro.BuildBulkBody(identities)
  if body then return #body end
  return bytes, buildError
end

local function sequentialBatches(assignments, maxBatches)
  maxBatches = DataUtils.PositiveInteger(maxBatches, MAX_BATCHES_PER_PULL) or 2
  local batches = {}
  for index = 1, maxBatches do batches[index] = { index = index, assignments = {} } end
  for position, assignment in ipairs(assignments) do
    local batchIndex = math.floor((position - 1) / MAX_ASSIGNMENTS_PER_BATCH) + 1
    if batchIndex > maxBatches then return nil, "pull-marker-capacity-exceeded" end
    batches[batchIndex].assignments[#batches[batchIndex].assignments + 1] = assignment
  end
  return batches
end

local function layoutScore(bytes, batches, layoutCode)
  local nonEmpty, maximumBytes, totalBytes, minimumBytes = 0, 0, 0, nil
  local counts = {}
  for index, batch in ipairs(batches) do
    local count = #(batch.assignments or {})
    counts[index] = count
    if count > 0 then
      nonEmpty = nonEmpty + 1
      local batchBytes = tonumber(bytes[index]) or 0
      maximumBytes = math.max(maximumBytes, batchBytes)
      totalBytes = totalBytes + batchBytes
      minimumBytes = minimumBytes and math.min(minimumBytes, batchBytes) or batchBytes
    end
  end
  return {
    nonEmpty,
    maximumBytes,
    totalBytes,
    maximumBytes - (minimumBytes or 0),
    counts[3] or 0,
    counts[2] or 0,
    layoutCode,
  }
end

local function scoreIsBetter(candidate, current)
  if not current then return true end
  for index = 1, #candidate do
    if candidate[index] < current[index] then return true end
    if candidate[index] > current[index] then return false end
  end
  return false
end

-- Macro slots are a byte-budget resource as well as a marker-count resource.
-- Search every canonical distribution across the allowed A/B/C batches. With
-- at most eight unique raid markers this is bounded and small, while allowing
-- long exact names to rebalance instead of blocking an otherwise safe pull.
local function assignBatches(assignments, pullIndex, routeFingerprint, automaticTargeting, maxBatches)
  maxBatches = DataUtils.PositiveInteger(maxBatches, MAX_BATCHES_PER_PULL) or 2
  if not automaticTargeting then return sequentialBatches(assignments, maxBatches) end
  local count = #assignments
  if count == 0 then return sequentialBatches(assignments, maxBatches) end
  local pullCapacity = math.min(MAX_EXECUTABLE_ASSIGNMENTS_PER_PULL, maxBatches * MAX_ASSIGNMENTS_PER_BATCH)
  if count > pullCapacity then return nil, "pull-marker-capacity-exceeded" end

  local bestBatches, bestScore
  local smallestFailedMaximum
  local firstNonLengthError
  local batches = {}
  for index = 1, maxBatches do batches[index] = { index = index, assignments = {} } end
  local choices = {}

  local function evaluate()
    local bytes, errors = {}, {}
    local maximumBytes = 0
    for batchIndex, batch in ipairs(batches) do
      local batchBytes, batchError = batchMacroLength(batch.assignments, batchIndex, pullIndex, routeFingerprint)
      bytes[batchIndex], errors[batchIndex] = batchBytes, batchError
      maximumBytes = math.max(maximumBytes, tonumber(batchBytes) or 0)
      if batchError and batchError ~= "smart-macro-too-long" then
        firstNonLengthError = firstNonLengthError or batchError
        return
      end
    end
    local hasError = false
    for batchIndex = 1, maxBatches do
      if errors[batchIndex] then hasError = true break end
    end
    if hasError or maximumBytes > 255 then
      if not smallestFailedMaximum or maximumBytes < smallestFailedMaximum then smallestFailedMaximum = maximumBytes end
      return
    end
    local layoutCode = 0
    for position = 1, #choices do layoutCode = layoutCode * maxBatches + (choices[position] - 1) end
    local score = layoutScore(bytes, batches, layoutCode)
    if scoreIsBetter(score, bestScore) then
      bestBatches, bestScore = DataUtils.DeepCopy(batches), score
    end
  end

  local function assign(position, highestUsedBatch)
    if position > count then
      evaluate()
      return
    end
    local assignment = assignments[position]
    local maxChoice = math.min(maxBatches, highestUsedBatch + 1)
    local firstChoice = position == 1 and 1 or 1
    local lastChoice = position == 1 and 1 or maxChoice
    for batchIndex = firstChoice, lastChoice do
      local batch = batches[batchIndex]
      if #batch.assignments < MAX_ASSIGNMENTS_PER_BATCH then
        batch.assignments[#batch.assignments + 1] = assignment
        choices[position] = batchIndex
        assign(position + 1, math.max(highestUsedBatch, batchIndex))
        choices[position] = nil
        batch.assignments[#batch.assignments] = nil
      end
    end
  end
  assign(1, 0)

  if not bestBatches then
    return nil, firstNonLengthError or "smart-macro-too-long", smallestFailedMaximum
  end

  for _, batch in ipairs(bestBatches) do
    for position, assignment in ipairs(batch.assignments) do
      assignment.batchIndex = batch.index
      assignment.batchPosition = position
    end
  end
  return bestBatches
end

local function estimatedBulkMacroLength(batch, pullIndex, routeFingerprint)
  if type(batch) ~= "table" then return 0 end
  return batchMacroLength(batch.assignments, batch.index, pullIndex, routeFingerprint)
end

local function buildPull(snapshot, snapshotPull, findings, runningTotal, routeNameTotals, resolvedRouteNameTotals, maxBatches, previousPull, nextPull)
  local pullPlan = {
    index = snapshotPull.index,
    status = "ready",
    assignments = {},
    markerUsage = {},
    markerPool = {},
    duplicateNPCs = {},
    batches = {},
    automaticTargeting = true,
    deathTracking = buildDeathTracking(snapshotPull),
  }
  local identityTotals = buildIdentityTotals(snapshotPull)
  local routeTotals = routeNameTotals or {}
  local resolvedRouteTotals = resolvedRouteNameTotals or {}
  local pullNameTotals = buildPullNameTotals(snapshotPull)
  local sourceNamesVerified = snapshot.targetNameLocaleStatus == "verified-client-locale"
  local resolvedPullNameTotals = buildResolvedPullNameTotals(snapshotPull, sourceNamesVerified)
  local adjacentPullNameTotals = {}
  local function mergeNeighborNames(neighbor)
    if type(neighbor) ~= "table" then return end
    for name, count in pairs(buildResolvedPullNameTotals(neighbor, sourceNamesVerified)) do
      adjacentPullNameTotals[name] = (adjacentPullNameTotals[name] or 0) + count
    end
  end
  mergeNeighborNames(previousPull)
  mergeNeighborNames(nextPull)
  local markedNameTotals = buildMarkedNameTotals(snapshotPull)
  local identityOrdinals = {}
  local seenAssignments = {}
  local path = ("pulls[%d]"):format(snapshotPull.index)

  for marker = 1, 8 do pullPlan.markerPool[marker] = "available" end

  for _, enemy in ipairs(snapshotPull.enemies or {}) do
    local identity = enemy.npcID and ("npc:"..enemy.npcID) or ("enemy:"..tostring(enemy.enemyIndex))
    for _, clone in ipairs(enemy.clones or {}) do
      identityOrdinals[identity] = (identityOrdinals[identity] or 0) + 1
      local marker = DataUtils.PositiveInteger(clone.marker, 8)
      if marker then
        if runningTotal >= MAX_ASSIGNMENTS then
          finding(findings, "error", "too-many-route-markers", "route", { maximum = MAX_ASSIGNMENTS })
          pullPlan.status = "blocked"
          return pullPlan, runningTotal, true
        end

        runningTotal = runningTotal + 1
        local assignment, assignmentError = buildAssignment(
          enemy, clone, marker, #pullPlan.assignments + 1, sourceNamesVerified
        )
        if not assignment then
          finding(findings, "error", assignmentError or "invalid-assignment", path)
          pullPlan.status = "blocked"
        elseif seenAssignments[assignment.id] then
          finding(findings, "error", "duplicate-assignment", path, { assignmentID = assignment.id })
          pullPlan.status = "blocked"
        else
          seenAssignments[assignment.id] = true
          assignment.cloneLabel = ("clone %d"):format(assignment.cloneIndex)
          assignment.duplicateOrdinal = identityOrdinals[identity]
          assignment.duplicateTotal = identityTotals[identity] or 1
          local exactName = assignment.targetName
          local sourceName = type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
          assignment.routeNameTotal = sourceName and (routeTotals[sourceName] or 0) or 0
          assignment.pullNameTotal = math.max(
            sourceName and (pullNameTotals[sourceName] or 0) or 0,
            exactName and (resolvedPullNameTotals[exactName] or 0) or 0,
            tonumber(assignment.duplicateTotal) or 1
          )
          assignment.dungeonNameTotal = sourceName and type(snapshot.enemyNameTotals) == "table"
            and (tonumber(snapshot.enemyNameTotals[sourceName]) or 0) or 0
          assignment.targetNameTotal = math.max(assignment.pullNameTotal, assignment.dungeonNameTotal)
          assignment.adjacentPullNameTotal = exactName and (adjacentPullNameTotals[exactName] or 0) or 0
          assignment.routeTargetNameTotal = exactName and (resolvedRouteTotals[exactName] or 0) or 0
          assignment.otherPullNameTotal = math.max(0, assignment.routeTargetNameTotal - (exactName and (resolvedPullNameTotals[exactName] or 0) or 0))
          assignment.targetNameScope = snapshot.enemyNameScope or "route-only"
          assignment.markedNameTotal = exactName and (markedNameTotals[exactName] or 0) or 0

          if not assignment.npcID then
            finding(findings, "error", "assignment-npc-identity-unavailable", path, {
              assignmentID = assignment.id,
              enemyIndex = assignment.enemyIndex,
              cloneIndex = assignment.cloneIndex,
            })
            pullPlan.status = "blocked"
          end

          if assignment.targetNameError then
            finding(findings, "error", assignment.targetNameError, path, {
              assignmentID = assignment.id,
              enemyIndex = assignment.enemyIndex,
              cloneIndex = assignment.cloneIndex,
            })
            pullPlan.status = "blocked"
          else
            pullPlan.assignments[#pullPlan.assignments + 1] = assignment
          end
        end
      end
    end
  end

  table.sort(pullPlan.assignments, assignmentSort)

  local executableCapacity = math.min(MAX_EXECUTABLE_ASSIGNMENTS_PER_PULL, maxBatches * MAX_ASSIGNMENTS_PER_BATCH)
  if #pullPlan.assignments > executableCapacity then
    finding(findings, "error", "pull-marker-capacity-exceeded", path, {
      count = #pullPlan.assignments,
      maximum = executableCapacity,
      macroCount = maxBatches,
      perMacro = MAX_ASSIGNMENTS_PER_BATCH,
    })
    pullPlan.status = "blocked"
  end

  local markerUsage, markerError = reserveExactMarkers(pullPlan.assignments, findings, path)
  if not markerUsage then
    pullPlan.status = "blocked"
    finding(findings, "error", markerError or "marker-allocation-failed", path)
  else
    pullPlan.markerUsage = markerUsage
    for marker, assignmentID in pairs(markerUsage) do pullPlan.markerPool[marker] = assignmentID end
  end

  if pullPlan.status ~= "blocked" and #pullPlan.assignments > 0 then
    pullPlan.automaticTargeting = classifyTargeting(pullPlan.assignments, findings, path)
    local batches, batchError, batchBytes = assignBatches(
      pullPlan.assignments, snapshotPull.index, snapshot.fingerprint, pullPlan.automaticTargeting, maxBatches
    )
    if not batches then
      finding(findings, "error", batchError or "batch-layout-not-executable", path, {
        bytes = batchBytes,
        maximum = 255,
        macroCount = maxBatches,
        perMacro = MAX_ASSIGNMENTS_PER_BATCH,
      })
      pullPlan.status = "blocked"
    else
      pullPlan.batches = batches
      if pullPlan.automaticTargeting then
        for _, batch in ipairs(batches) do
          local bytes, lengthError = estimatedBulkMacroLength(batch, snapshotPull.index, snapshot.fingerprint)
          if lengthError or (bytes and bytes > 255) then
            finding(findings, "error", lengthError or "smart-macro-too-long", path, {
              batchIndex = batch.index,
              bytes = bytes,
              maximum = 255,
            })
            pullPlan.status = "blocked"
          end
        end
      else
        pullPlan.status = "manual-required"
      end
    end
  end

  for identity, count in pairs(identityTotals) do
    if count > 1 then pullPlan.duplicateNPCs[#pullPlan.duplicateNPCs + 1] = { identity = identity, count = count } end
  end
  table.sort(pullPlan.duplicateNPCs, function(left, right) return left.identity < right.identity end)

  return pullPlan, runningTotal, false
end

function MarkerPlanner.Build(snapshot, options)
  options = type(options) == "table" and options or {}
  local maxBatches = DataUtils.PositiveInteger(options.maxBatches, MAX_BATCHES_PER_PULL) or 2
  if type(snapshot) ~= "table" or DataUtils.IsSecret(snapshot) then
    return nil, { { severity = "error", code = "snapshot-unavailable", path = "route" } }
  end
  if type(snapshot.pulls) ~= "table" or not snapshot.fingerprint or not snapshot.routeKey then
    return nil, { { severity = "error", code = "snapshot-invalid", path = "route" } }
  end

  local findings = {}
  local plan = {
    modelVersion = 18,
    routeKey = snapshot.routeKey,
    routeFingerprint = snapshot.fingerprint,
    observedFingerprint = snapshot.fingerprint,
    dungeonIndex = snapshot.dungeonIndex,
    dungeonName = snapshot.dungeonName,
    challengeMapID = snapshot.challengeMapID,
    presetName = snapshot.presetName,
    sourceMode = snapshot.sourceMode,
    mdtVersion = snapshot.mdtVersion,
    status = "ready",
    options = {
      preserveExistingMarkers = true,
      primaryMarkersOverrideExisting = false,
      exactMDTMarkers = true,
      automaticPullReset = true,
      deathProgressAdvisory = true,
      maxBatches = maxBatches,
    },
    pulls = {},
    summary = {
      routePulls = #snapshot.pulls,
      markedPulls = 0,
      assignments = 0,
      automaticPulls = 0,
      manualRequiredPulls = 0,
      localizedTargets = 0,
      unresolvedTargetNames = 0,
      deathTrackablePulls = 0,
      errors = 0,
      warnings = 0,
    },
  }

  local routeNameTotals = buildRouteNameTotals(snapshot)
  local sourceNamesVerified = snapshot.targetNameLocaleStatus == "verified-client-locale"
  local resolvedRouteNameTotals = buildResolvedRouteNameTotals(snapshot, sourceNamesVerified)
  local total, overflow = 0, false
  for snapshotPosition, snapshotPull in ipairs(snapshot.pulls) do
    local pullPlan
    pullPlan, total, overflow = buildPull(
      snapshot, snapshotPull, findings, total, routeNameTotals, resolvedRouteNameTotals, maxBatches,
      snapshot.pulls[snapshotPosition - 1], snapshot.pulls[snapshotPosition + 1]
    )
    if #pullPlan.assignments > 0 then
      plan.pulls[#plan.pulls + 1] = pullPlan
      plan.summary.assignments = plan.summary.assignments + #pullPlan.assignments
      if pullPlan.status == "manual-required" then
        plan.summary.manualRequiredPulls = plan.summary.manualRequiredPulls + 1
      elseif pullPlan.status ~= "blocked" then
        plan.summary.automaticPulls = plan.summary.automaticPulls + 1
      end
      if pullPlan.deathTracking and pullPlan.deathTracking.available then
        plan.summary.deathTrackablePulls = plan.summary.deathTrackablePulls + 1
      end
    end
    if overflow then break end
  end

  plan.summary.markedPulls = #plan.pulls
  for _, pull in ipairs(plan.pulls or {}) do
    for _, assignment in ipairs(pull.assignments or {}) do
      if assignment.targetNameVerified == true then
        if assignment.targetNameResolution == "localized-tooltip" then
          plan.summary.localizedTargets = plan.summary.localizedTargets + 1
        end
      else
        plan.summary.unresolvedTargetNames = plan.summary.unresolvedTargetNames + 1
      end
    end
  end
  if plan.summary.assignments > 0 and plan.summary.unresolvedTargetNames > 0 then
    finding(findings, "error", "target-name-locale-unverified", "route", {
      locale = snapshot.clientLocale,
      unresolved = plan.summary.unresolvedTargetNames,
      localized = plan.summary.localizedTargets,
    })
  end
  if plan.summary.assignments == 0 then finding(findings, "warning", "route-has-no-markers", "route") end
  if snapshot.nativeAssignmentsAvailable ~= true then finding(findings, "warning", "native-marker-data-unavailable", "route") end

  for _, item in ipairs(findings) do
    if item.severity == "error" then
      plan.summary.errors = plan.summary.errors + 1
    elseif item.severity == "warning" then
      plan.summary.warnings = plan.summary.warnings + 1
    end
  end

  if plan.summary.errors > 0 then
    plan.status = "blocked"
  elseif plan.summary.warnings > 0 then
    plan.status = "ready-with-warnings"
  end
  return plan, findings
end

function MarkerPlanner.GetPull(plan, pullIndex)
  if type(plan) ~= "table" then return nil end
  pullIndex = DataUtils.PositiveInteger(pullIndex)
  if not pullIndex then return nil end
  for _, pull in ipairs(plan.pulls or {}) do
    if pull.index == pullIndex then return pull end
  end
end

MarkerPlanner.MaxAssignments = MAX_ASSIGNMENTS
MarkerPlanner.MaxAssignmentsPerPull = MAX_EXECUTABLE_ASSIGNMENTS_PER_PULL
MarkerPlanner.MaxAssignmentsPerBatch = MAX_ASSIGNMENTS_PER_BATCH
MarkerPlanner.MaxBatchesPerPull = MAX_BATCHES_PER_PULL