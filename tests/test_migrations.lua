local Addon = {
  IsSecret = function() return false end,
}

local dataUtils = assert(loadfile("Core/DataUtils.lua"))
dataUtils("MDTPullMarker", Addon)
local migrations = assert(loadfile("Core/Migrations.lua"))
migrations("MDTPullMarker", Addon)

local function binding()
  return {
    routeKey = "uid:test-route",
    presetUID = "test-route",
    presetName = "Migration test",
    presetIndex = 2,
    dungeonIndex = 42,
    challengeMapID = 504,
    boundFingerprint = "route-v3-test",
    mdtVersion = "6.2.1",
  }
end

-- Schema 10 is the rc45 schema that introduced one explicit routeBinding.
-- Upgrading it must preserve that binding in the schema-11+ per-dungeon map.
local migrated10, info10 = Addon.Migrations.Run({
  schemaVersion = 10,
  global = {},
  routeBinding = binding(),
})
assert(migrated10, "schema 10 migration unexpectedly failed")
assert(info10 and info10.from == 10 and info10.to == Addon.Migrations.CurrentSchema, "schema 10 migration metadata is incorrect")
assert(migrated10.schemaVersion == 12, "schema 10 migration did not reach the current schema")
assert(migrated10.routeBinding == nil, "legacy single routeBinding must be retired after conversion")
assert(type(migrated10.routeBindings) == "table" and type(migrated10.routeBindings[42]) == "table", "rc45 route binding was lost during conversion")
assert(migrated10.routeBindings[42].routeKey == "uid:test-route", "route identity changed during conversion")
assert(migrated10.routeBindings[42].challengeMapID == 504, "challenge map identity changed during conversion")
assert(migrated10.lastRouteDungeonIndex == 42, "last bound dungeon was not preserved")

-- Schema 9 predates route binding. A stray/foreign routeBinding must not become
-- authoritative during the 9 -> 10 migration; rc45 intentionally started old
-- installations unbound until the user explicitly bound a route.
local migrated9 = assert(Addon.Migrations.Run({
  schemaVersion = 9,
  global = {},
  routeBinding = binding(),
}))
assert(migrated9.routeBinding == nil, "pre-binding schema retained a foreign routeBinding")
assert(type(migrated9.routeBindings) == "table" and next(migrated9.routeBindings) == nil, "pre-binding schema unexpectedly promoted a route binding")
assert(migrated9.lastRouteDungeonIndex == nil, "pre-binding schema unexpectedly selected a bound dungeon")

print("ok - route binding migrations")
