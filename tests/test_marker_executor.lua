local inCombat = false
local markPendingCalls = 0

function InCombatLockdown()
  return inCombat
end

function GetTimePreciseSec()
  return 100.0
end

function IsInInstance()
  return true, "party"
end

local function buildAddon(assignments)
  local manager = {
    pending = false,
  }

  function manager:MarkPending()
    self.pending = true
    markPendingCalls = markPendingCalls + 1
  end

  function manager:IsPending()
    return self.pending
  end

  function manager:ParkAllManagedExecution(_reason)
    return true, 0
  end

  function manager:RefreshAll()
    return {}, nil
  end

  function manager:RefreshPrimary()
    return {}, nil
  end

  function manager:RefreshDescriptorSet()
    return {}, nil
  end

  function manager:GetStatus()
    return {}
  end

  function manager:GetDescriptorSetStatus()
    return {}
  end

  function manager:ParkRecognizedRouteMacros()
    return true, 0
  end

  function manager:RetireRecognizedRouteMacros()
    return true, 0
  end

  local addon = {
    Constants = {
      SmartButtonName = "MDTPullMarkerSmartButton",
      SmartMacroName = "MDTPM1",
      SmartMacroName2 = "MDTPM2",
    },
    MarkerMacro = {
      BULK_MARKER_LIMIT = 3,
      SAFE_IDLE_MACRO = "#showtooltip\n/stopmacro",
      SanitizeTargetName = function(value)
        if type(value) ~= "string" or value == "" then
          return nil, "assignment-target-name-unavailable"
        end
        return value
      end,
      ParseBulkToken = function(token)
        if token == "batch4" then return nil, 4 end
        return nil, 1
      end,
      BuildBulkToken = function()
        return "batch1"
      end,
      BuildBulkBody = function()
        return "#showtooltip\n/stopmacro"
      end,
    },
    SmartMacroManager = {
      Create = function()
        return manager
      end,
    },
    MDT = {
      GetRouteBinding = function()
        return nil
      end,
    },
    RuntimeController = {
      GetState = function()
        return {
          planStatus = "ready",
          completed = false,
          allAssignmentsConfirmed = false,
          assignmentConfirmed = false,
          currentPullIndex = 1,
          currentPullPosition = 1,
          pullCount = 1,
          routeFingerprint = "route-a",
          automaticTargeting = true,
          pullStatus = "ready",
        }
      end,
      GetOrderedAssignments = function()
        return assignments or {}
      end,
      OnBatchSubmitted = function()
        return true, "batch-submitted"
      end,
    },
    DungeonSession = {
      GetState = function()
        return {
          active = true,
          challengeCompleted = false,
          routeMatches = true,
        }
      end,
    },
    MarkerOwnership = {
      IsOwner = function()
        return true, "owner", "Player-Realm"
      end,
      GetState = function()
        return { owner = "Player-Realm" }
      end,
    },
    RuntimeFrame = {
      IsOpen = function()
        return false
      end,
      Refresh = function() end,
    },
    PullDeathTracker = {
      GetState = function()
        return {}
      end,
    },
  }

  function addon.IsSecret(_value)
    return false
  end

  return addon, manager
end

local function loadExecutor(assignments)
  local addon, manager = buildAddon(assignments)
  local chunk = assert(loadfile("Runtime/MarkerExecutor.lua"))
  chunk("MDTPullMarker", addon)
  assert(addon.MarkerExecutor, "MarkerExecutor was not loaded")
  return addon.MarkerExecutor, manager
end

-- Bulk confirmation is only valid once the pull is in combat.
inCombat = false
markPendingCalls = 0
local executor = loadExecutor({})
local confirmed, reason = executor:ConfirmBulk("batch1", "test-out-of-combat")
assert(confirmed == nil, "bulk confirmation outside combat must fail")
assert(reason == "bulk-requires-combat", "outside-combat bulk rejection changed")

-- Once execution is invalidated, the same runtime must fail closed even after
-- combat begins. Combat lockdown may mark a refresh pending but must not try to
-- repair protected state immediately.
inCombat = true
local invalidated, invalidateReason = executor:InvalidateExecution("route-stale")
assert(invalidated == false, "combat invalidation must not claim protected state was repaired")
assert(invalidateReason == "in-combat", "combat invalidation must report in-combat")
assert(markPendingCalls == 1, "combat invalidation must mark protected refresh pending")
confirmed, reason = executor:ConfirmBulk("batch1", "test-invalidated")
assert(confirmed == nil, "invalidated execution must reject bulk submission")
assert(reason == "route-stale", "invalidation reason must propagate through the execution gate")

-- Route batch indexes above three are rejected behaviourally, not merely by a
-- source assertion.
inCombat = true
executor = loadExecutor({})
confirmed, reason = executor:ConfirmBulk("batch4", "test-batch-cap")
assert(confirmed == nil, "batch four must never be executable")
assert(reason == "bulk-batch-invalid", "batch index cap changed")

-- More than three executable assignments in one batch must fail before token
-- confirmation or submission state can advance.
local tooMany = {}
for index = 1, 4 do
  tooMany[index] = {
    id = "E"..index..":C1",
    batchIndex = 1,
    batchPosition = index,
    marker = index,
    requestedMarker = index,
    enemyIndex = index,
    cloneIndex = 1,
    npcID = 1000 + index,
    targetName = "Mob"..index,
    executionMethod = "exact-name",
    automaticTargeting = true,
  }
end
executor = loadExecutor(tooMany)
confirmed, reason = executor:ConfirmBulk("batch1", "test-assignment-cap")
assert(confirmed == nil, "four assignments in one batch must be rejected")
assert(reason == "bulk-batch-over-capacity", "per-batch execution cap changed")

print("ok - marker executor behavioral gates and capacity invariants")
