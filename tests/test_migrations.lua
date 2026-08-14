local Addon = {
  IsSecret = function() return false end,
}

local dataUtils = assert(loadfile("Core/DataUtils.lua"))
dataUtils("MDTPullMarker", Addon)
local migrations = assert(loadfile("Core/Migrations.lua"))
migrations("MDTPullMarker", Addon)

local legacyBinding = {
  routeKey = "uid:test-route",
  presetUID = "test-route",
  presetName = "Migration test",
  presetIndex = 2,
  dungeonIndex = 42,
  challengeMapID = 504,
  boundFingerprint = "route-v3-test",
  mdtVersion = "6.2.1",
}

local migrated, info = Addon.Migrations.Run({
  schemaVersion = 9,
  global = {},
  routeBinding = legacyBinding,
})

assert(migrated, "schema 9 migration unexpectedly failed")
assert(info and info.from == 9 and info.to == Addon.Migrations.CurrentSchema, "migration metadata is incorrect")
assert(migrated.schemaVersion == 12, "migration did not reach the current schema")
assert(migrated.routeBinding == nil, "legacy single routeBinding must be retired after conversion")
assert(type(migrated.routeBindings) == "table", "routeBindings map was not created")
assert(type(migrated.routeBindings[42]) == "table", "legacy bound route was lost during migration")
assert(migrated.routeBindings[42].routeKey == legacyBinding.routeKey, "route identity changed during migration")
assert(migrated.routeBindings[42].challengeMapID == legacyBinding.challengeMapID, "challenge map identity changed during migration")
assert(migrated.lastRouteDungeonIndex == 42, "last bound dungeon was not preserved")

print("ok - route binding migration")
