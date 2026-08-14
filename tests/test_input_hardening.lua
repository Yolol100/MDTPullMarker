local Addon = {
  IsSecret = function(value)
    return type(value) == "table" and value.__secret == true
  end,
}

local function loadModule(path)
  local chunk, loadError = loadfile(path)
  assert(chunk, loadError)
  chunk("MDTPullMarker", Addon)
end

loadModule("Core/DataUtils.lua")
loadModule("Core/MarkerMacro.lua")

local DataUtils = assert(Addon.DataUtils)
local MarkerMacro = assert(Addon.MarkerMacro)

-- Secret/invalid values must fail closed before they can become identifiers,
-- hashes, macro targets, or persisted route data.
local secret = { __secret = true }
assert(DataUtils.StableHash(secret) == nil)
assert(DataUtils.SafeString(secret, 20, false) == nil)
assert(DataUtils.SafeNumber(0 / 0) == nil)
assert(DataUtils.SafeNumber(math.huge) == nil)
assert(DataUtils.PositiveInteger(0) == nil)
assert(DataUtils.PositiveInteger(9, 8) == nil)

-- Display strings may be clipped safely, but identity strings must never be
-- silently rewritten by truncation.
local euro = "\226\130\172"
assert(DataUtils.UTF8SafePrefix("A" .. euro .. "B", 3) == "A")
assert(DataUtils.UTF8SafePrefix("A" .. euro .. "B", 4) == "A" .. euro)
assert(DataUtils.SafeString("  abcdef  ", 3, false) == "abc")
assert(DataUtils.ValidatedString("  abcdef  ", 3, false) == nil)

-- Recursive input is bounded against cycles, pathological depth, entry floods,
-- and unsupported key/value types.
local cyclic = {}
cyclic.self = cyclic
local copied, err = DataUtils.DeepCopy(cyclic)
assert(copied == nil and err == "cycle")

local deep = { a = { b = { c = true } } }
copied, err = DataUtils.DeepCopy(deep, { maxDepth = 2 })
assert(copied == nil and err == "max-depth")

copied, err = DataUtils.DeepCopy({ a = 1, b = 2, c = 3 }, { maxEntries = 2 })
assert(copied == nil and err == "max-entries")

copied, err = DataUtils.DeepCopy({ [function() end] = true })
assert(copied == nil and err == "unsupported-key-type:function")

-- Target names are a macro-injection boundary. Newlines, semicolons, brackets,
-- control characters, and overlong names must never enter a secure macro body.
for _, unsafe in ipairs({
  "Mob; /run print('x')",
  "Mob[foo]",
  "Mob\n/tm 8",
  "Mob\r/target player",
}) do
  local name, reason = MarkerMacro.SanitizeTargetName(unsafe)
  assert(name == nil and reason == "unsafe-target-name", "unsafe target name was accepted: " .. unsafe)
end
local longName, longReason = MarkerMacro.SanitizeTargetName(string.rep("A", 121))
assert(longName == nil and longReason == "target-name-too-long")
assert(MarkerMacro.SanitizeTargetName(secret) == nil)

local identities = {
  {
    pullIndex = 1,
    batchIndex = 1,
    routeFingerprint = "route-abc",
    assignmentID = "E1:C1",
    marker = 8,
    targetName = "Dangerous Mob",
    executionMethod = "exact-name",
  },
  {
    pullIndex = 1,
    batchIndex = 1,
    routeFingerprint = "route-abc",
    assignmentID = "E2:C1",
    marker = 7,
    targetName = "Caster Mob",
    executionMethod = "exact-name",
  },
}

local body = assert(MarkerMacro.BuildBulkBody(identities))
assert(body:match("^/stopmacro %[nocombat%]"), "bulk macros must fail closed outside combat")
assert(body:find("/targetexact Dangerous Mob", 1, true))
assert(body:find("/tm [harm,nodead] ~8", 1, true), "markers must preserve existing target markers")
assert(MarkerMacro.IsRecognizedBody(body) == true, "self-generated bulk macro must be recognized")

-- The recognition gate must reject lookalike macros with arbitrary commands or
-- altered marker semantics even when they contain a valid-looking completion token.
local injected = body:gsub("/cleartarget", "/run print('x')", 1)
assert(MarkerMacro.IsRecognizedBody(injected) == false)
local overwrite = body:gsub("~8", "8", 1)
assert(MarkerMacro.IsRecognizedBody(overwrite) == false)

local tooMany = { identities[1], identities[2], identities[1], identities[2] }
local oversized, oversizedReason = MarkerMacro.BuildBulkBody(tooMany)
assert(oversized == nil and oversizedReason == "bulk-batch-over-capacity")

local ambiguous = {
  pullIndex = 1,
  batchIndex = 1,
  routeFingerprint = "route-abc",
  assignmentID = "E3:C1",
  marker = 6,
  targetName = "Same Name",
  executionMethod = "manual",
}
local unavailable, unavailableReason = MarkerMacro.BuildBulkBody({ ambiguous })
assert(unavailable == nil and unavailableReason == "same-name-automatic-targeting-unavailable")

print("ok - bounded inputs and secure macro injection boundary")
