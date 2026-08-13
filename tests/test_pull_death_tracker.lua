local SECRET = {}

local function positiveInteger(value)
  local number = tonumber(value)
  if not number or number <= 0 or number % 1 ~= 0 then return nil end
  return number
end

local pull = {
  deathTracking = {
    available = true,
    expectedTotal = 1,
    expectedByNPC = { [123] = 1 },
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
Tracker:OnCombatStarted()
local accepted, progressReason = Tracker:OnUnitDied("Creature-0-0-0-0-123-0000000001")
assert(accepted == true, progressReason)
assert(progressReason == "expected-pull-deaths-observed", progressReason)
local complete, verdict = Tracker:GetCompletionVerdict(1)
assert(complete == true and verdict == "death-complete", tostring(verdict))
Tracker:OnCombatEnded()

Tracker:OnCombatStarted()
local restricted, restrictedReason = Tracker:OnUnitDied(SECRET)
assert(restricted == false and restrictedReason == "unit-died-guid-secret", tostring(restrictedReason))
local restrictedVerdict, restrictedStatus = Tracker:GetCompletionVerdict(1)
assert(restrictedVerdict == nil and restrictedStatus == "death-tracking-restricted", tostring(restrictedStatus))

print("ok - pull death tracker")
