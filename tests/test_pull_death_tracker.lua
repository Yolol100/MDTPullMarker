local SECRET = {}

local function positiveInteger(value)
  local number = tonumber(value)
  if not number or number <= 0 or number % 1 ~= 0 then return nil end
  return number
end

local pull = {
  deathTracking = {
    available = true,
    expectedTotal = 2,
    expectedByNPC = { [123] = 2 },
    mode = "unit-death-gated",
  },
}

local Addon = {
  DataUtils = { PositiveInteger = positiveInteger },
  IsSecret = function(value) return value == SECRET end,
  RuntimeController = {
    GetState = function()
      return { routeFingerprint = "route:test", currentPullIndex = 1 }
    end,
    GetPullByIndex = function(_, pullIndex)
      if pullIndex == 1 then return pull end
    end,
  },
  MDT = { GetRouteBinding = function() return nil end },
  MarkerExecutor = { OnPullDeathProgress = function() end },
}

local chunk = assert(loadfile("Runtime/PullDeathTracker.lua"))
chunk("MDTPullMarker", Addon)
local Tracker = assert(Addon.PullDeathTracker)

Tracker:Initialize()
local outside, outsideReason = Tracker:OnUnitDied("Creature-0-0-0-0-123-0000000000")
assert(outside == false and outsideReason == "outside-combat", tostring(outsideReason))

Tracker:OnCombatStarted()
local accepted, progressReason = Tracker:OnUnitDied("Creature-0-0-0-0-123-0000000001")
assert(accepted == true and progressReason == "pull-death-progress", tostring(progressReason))
local complete, verdict = Tracker:GetCompletionVerdict(1)
assert(complete == false and verdict == "death-incomplete", tostring(verdict))

local duplicate, duplicateReason = Tracker:OnUnitDied("Creature-0-0-0-0-123-0000000001")
assert(duplicate == false and duplicateReason == "death-already-counted", tostring(duplicateReason))
local unrelated, unrelatedReason = Tracker:OnUnitDied("Creature-0-0-0-0-999-0000000001")
assert(unrelated == false and unrelatedReason == "death-not-active-pull-npc", tostring(unrelatedReason))

accepted, progressReason = Tracker:OnUnitDied("Creature-0-0-0-0-123-0000000002")
assert(accepted == true and progressReason == "expected-pull-deaths-observed", tostring(progressReason))
complete, verdict = Tracker:GetCompletionVerdict(1)
assert(complete == true and verdict == "death-complete", tostring(verdict))
Tracker:OnCombatEnded()

Tracker:OnCombatStarted()
local restricted, restrictedReason = Tracker:OnUnitDied(SECRET)
assert(restricted == false and restrictedReason == "unit-died-guid-secret", tostring(restrictedReason))
local restrictedVerdict, restrictedStatus = Tracker:GetCompletionVerdict(1)
assert(restrictedVerdict == nil and restrictedStatus == "death-tracking-restricted", tostring(restrictedStatus))
Tracker:OnCombatEnded()

Tracker:OnCombatStarted()
local missing, missingReason = Tracker:OnUnitDied(nil)
assert(missing == false and missingReason == "unit-died-guid-unavailable", tostring(missingReason))
local missingVerdict, missingStatus = Tracker:GetCompletionVerdict(1)
assert(missingVerdict == false and missingStatus == "death-tracking-unavailable", tostring(missingStatus))

print("ok - pull death tracker")
