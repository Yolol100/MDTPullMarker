local _, Addon = ...

local RouteMacroPlan = {}
Addon.RouteMacroPlan = RouteMacroPlan

local DataUtils = Addon.DataUtils
local MarkerMacro = Addon.MarkerMacro

local MAX_PULL_INDEX = 500
local MACRO_PREFIX = "MPM"
local MAX_BATCH_INDEX = 3
local BATCH_SUFFIX = { [1] = "A", [2] = "B", [3] = "C" }

local function copy(value)
  return DataUtils.DeepCopy(value)
end

local function macroName(pullIndex, batchIndex)
  pullIndex = DataUtils.PositiveInteger(pullIndex, MAX_PULL_INDEX)
  batchIndex = DataUtils.PositiveInteger(batchIndex, MAX_BATCH_INDEX)
  if not pullIndex or not batchIndex then return nil end
  return ("%s%03d%s"):format(MACRO_PREFIX, pullIndex, BATCH_SUFFIX[batchIndex])
end

local function identitiesForBatch(plan, pull, batch)
  local result = {}
  for _, assignment in ipairs(batch.assignments or {}) do
    result[#result + 1] = {
      assignmentID = assignment.id,
      marker = assignment.marker,
      targetName = assignment.targetName or assignment.name,
      executionMethod = assignment.executionMethod,
      pullIndex = pull.index,
      routeFingerprint = plan.routeFingerprint,
      batchIndex = batch.index,
      batchPosition = assignment.batchPosition,
      npcID = assignment.npcID,
      enemyIndex = assignment.enemyIndex,
      cloneIndex = assignment.cloneIndex,
      useSetUnmarked = true,
    }
  end
  return result
end

function RouteMacroPlan.Build(plan)
  if type(plan) ~= "table" or DataUtils.IsSecret(plan) then return nil, "marker-plan-unavailable" end
  if plan.status == "blocked" then return nil, "marker-plan-blocked" end
  if type(plan.routeFingerprint) ~= "string" or plan.routeFingerprint == "" then return nil, "route-fingerprint-unavailable" end

  local result = {
    version = 1,
    routeKey = plan.routeKey,
    routeFingerprint = plan.routeFingerprint,
    presetName = plan.presetName,
    dungeonName = plan.dungeonName,
    descriptors = {},
    byToken = {},
    byPull = {},
    manualPulls = {},
    summary = {
      markedPulls = #(plan.pulls or {}),
      executablePulls = 0,
      manualPulls = 0,
      macroCount = 0,
    },
  }

  for _, pull in ipairs(plan.pulls or {}) do
    local pullIndex = DataUtils.PositiveInteger(pull.index, MAX_PULL_INDEX)
    if not pullIndex then return nil, "pull-index-invalid" end
    if pull.status == "manual-required" or pull.automaticTargeting == false then
      result.manualPulls[#result.manualPulls + 1] = pullIndex
      result.summary.manualPulls = result.summary.manualPulls + 1
    elseif pull.status ~= "blocked" then
      local createdForPull = 0
      for _, batch in ipairs(pull.batches or {}) do
        if type(batch.assignments) == "table" and #batch.assignments > 0 then
          local batchIndex = DataUtils.PositiveInteger(batch.index, MAX_BATCH_INDEX)
          local name = macroName(pullIndex, batchIndex)
          if not name then return nil, "route-macro-name-invalid" end
          local identities = identitiesForBatch(plan, pull, batch)
          local body, bodyError, bytes = MarkerMacro.BuildBulkBody(identities)
          if not body then return nil, bodyError or "route-macro-body-unavailable", bytes end
          local token = MarkerMacro.BuildBulkToken(identities)
          if not token then return nil, "route-macro-token-invalid" end
          if result.byToken[token] then return nil, "route-macro-token-collision" end
          local descriptor = {
            name = name,
            body = body,
            token = token,
            bytes = #body,
            pullIndex = pullIndex,
            batchIndex = batchIndex,
            assignmentCount = #identities,
            identities = identities,
            label = ("Pull %d%s"):format(pullIndex, BATCH_SUFFIX[batchIndex]),
          }
          result.descriptors[#result.descriptors + 1] = descriptor
          result.byToken[token] = descriptor
          result.byPull[pullIndex] = result.byPull[pullIndex] or {}
          result.byPull[pullIndex][batchIndex] = descriptor
          createdForPull = createdForPull + 1
        end
      end
      if createdForPull > 0 then result.summary.executablePulls = result.summary.executablePulls + 1 end
    end
  end

  table.sort(result.descriptors, function(left, right)
    if left.pullIndex ~= right.pullIndex then return left.pullIndex < right.pullIndex end
    return left.batchIndex < right.batchIndex
  end)
  result.summary.macroCount = #result.descriptors
  return result
end

function RouteMacroPlan.ResolveToken(routeMacroPlan, token)
  if type(routeMacroPlan) ~= "table" or type(routeMacroPlan.byToken) ~= "table" then return nil end
  local descriptor = routeMacroPlan.byToken[tostring(token or "")]
  return descriptor and copy(descriptor) or nil
end

function RouteMacroPlan.GetDescriptor(routeMacroPlan, pullIndex, batchIndex)
  pullIndex = DataUtils.PositiveInteger(pullIndex, MAX_PULL_INDEX)
  batchIndex = DataUtils.PositiveInteger(batchIndex, MAX_BATCH_INDEX)
  local byPull = type(routeMacroPlan) == "table" and routeMacroPlan.byPull or nil
  local descriptor = pullIndex and batchIndex and type(byPull) == "table" and byPull[pullIndex] and byPull[pullIndex][batchIndex] or nil
  return descriptor and copy(descriptor) or nil
end

function RouteMacroPlan.GetMacroName(pullIndex, batchIndex)
  return macroName(pullIndex, batchIndex)
end

function RouteMacroPlan.Copy(routeMacroPlan)
  return copy(routeMacroPlan)
end
