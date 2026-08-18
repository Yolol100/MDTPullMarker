local Addon = {
  IsSecret = function() return false end,
}

local dataUtils = assert(loadfile("Core/DataUtils.lua"))
dataUtils("MDTPullMarker", Addon)
local migrations = assert(loadfile("Core/Migrations.lua"))
migrations("MDTPullMarker", Addon)

local function currentDB(backups)
  return {
    schemaVersion = Addon.Migrations.CurrentSchema,
    global = {},
    routeBindings = {},
    backups = backups or {},
  }
end

local function countEntries(value, seen)
  if type(value) ~= "table" then return 0 end
  seen = seen or {}
  if seen[value] then return 0 end
  seen[value] = true
  local count = 0
  for _, child in pairs(value) do
    count = count + 1 + countEntries(child, seen)
  end
  return count
end

-- Small valid archival data is preserved exactly.
local small = assert(Addon.Migrations.Run(currentDB({
  { createdAt = "now", schemaVersion = 11, data = { note = "keep-me", nested = { value = 42 } } },
})))
assert(#small.backups == 1, "valid backup disappeared")
assert(small.backups[1].data.note == "keep-me", "valid backup string changed")
assert(small.backups[1].data.nested.value == 42, "valid nested backup value changed")
assert(small.backups[1].truncated == false, "valid backup was incorrectly marked truncated")

-- Oversized legacy strings are clipped at a UTF-8-safe byte boundary.
local huge = string.rep("x", Addon.Migrations.MaxBackupStringBytes + 5000)
local clipped = assert(Addon.Migrations.Run(currentDB({
  { createdAt = "now", schemaVersion = 5, data = { note = huge } },
})))
assert(#clipped.backups[1].data.note <= Addon.Migrations.MaxBackupStringBytes, "oversized backup string was not bounded")
assert(clipped.backups[1].truncated == true, "bounded string was not marked truncated")

local utf8Huge = string.rep("é", 3000)
local utf8Clipped = assert(Addon.Migrations.Run(currentDB({
  { createdAt = "now", schemaVersion = 5, data = { note = utf8Huge } },
})))
local utf8Note = utf8Clipped.backups[1].data.note
assert(#utf8Note <= Addon.Migrations.MaxBackupStringBytes, "UTF-8 backup string exceeded byte cap")
assert(not utf8Note:match("[\128-\191]$"), "UTF-8 backup string ended on a continuation byte")

-- Cyclic/foreign archival content cannot poison normal startup.
local cyclicData = { label = "safe" }
cyclicData.self = cyclicData
local cyclic = assert(Addon.Migrations.Run(currentDB({
  { createdAt = "now", schemaVersion = 7, data = cyclicData },
})))
assert(cyclic.backups[1].data.label == "safe", "safe data around a cycle was lost")
assert(cyclic.backups[1].data.self == nil, "cycle survived backup sanitization")
assert(cyclic.backups[1].truncated == true, "cycle removal was not recorded")

-- Entry floods are bounded instead of being copied into SavedVariables forever.
local floodedData = {}
for index = 1, Addon.Migrations.MaxBackupEntries + 1000 do floodedData["key"..index] = index end
local flooded = assert(Addon.Migrations.Run(currentDB({
  { createdAt = "now", schemaVersion = 4, data = floodedData },
})))
assert(countEntries(flooded.backups[1].data) <= Addon.Migrations.MaxBackupEntries, "backup entry cap was exceeded")
assert(flooded.backups[1].truncated == true, "entry-flood truncation was not recorded")

-- Deep archival structures stop at the depth budget without failing startup.
local deepRoot, cursor = {}, nil
cursor = deepRoot
for depth = 1, Addon.Migrations.MaxBackupDepth + 5 do
  cursor.child = { depth = depth }
  cursor = cursor.child
end
local deep = assert(Addon.Migrations.Run(currentDB({
  { createdAt = "now", schemaVersion = 3, data = deepRoot },
})))
assert(deep.backups[1].truncated == true, "deep backup was not marked truncated")

-- Only the newest two archive slots survive normalization.
local limited = assert(Addon.Migrations.Run(currentDB({
  { createdAt = "one", schemaVersion = 1, data = { id = 1 } },
  { createdAt = "two", schemaVersion = 2, data = { id = 2 } },
  { createdAt = "three", schemaVersion = 3, data = { id = 3 } },
})))
assert(#limited.backups == Addon.Migrations.MaxBackups, "backup count cap changed")
assert(limited.backups[1].data.id == 1 and limited.backups[2].data.id == 2, "backup ordering changed")

-- The new backup created during a real schema migration is bounded too.
local migrated = assert(Addon.Migrations.Run({
  schemaVersion = 10,
  global = {},
  legacyDiagnosticBlob = huge,
  routeBinding = {
    routeKey = "uid:test-route",
    presetUID = "test-route",
    presetName = "Migration test",
    presetIndex = 2,
    dungeonIndex = 42,
    challengeMapID = 504,
    boundFingerprint = "route-v3-test",
    mdtVersion = "6.2.4",
  },
}))
assert(#migrated.backups >= 1, "migration did not create a recovery backup")
assert(#migrated.backups[1].data.legacyDiagnosticBlob <= Addon.Migrations.MaxBackupStringBytes, "new migration backup kept an oversized string")
assert(migrated.backups[1].truncated == true, "new migration backup truncation was not recorded")
assert(migrated.routeBindings[42].routeKey == "uid:test-route", "backup hardening changed the actual migration result")

print("ok - bounded migration backup scenarios")
