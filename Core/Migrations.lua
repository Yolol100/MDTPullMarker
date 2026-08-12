local _, Addon = ...

local Migrations = {}
Addon.Migrations = Migrations

local DataUtils = Addon.DataUtils
local CURRENT_SCHEMA = 12
local MAX_BACKUPS = 2

local function timestamp()
  if type(date) == "function" then return date("%Y-%m-%d %H:%M:%S") end
  return "unknown-time"
end

local function freshGlobal()
  return {
    preserveExistingMarkers = true,
    debug = false,
    firstRun = true,
    logs = {},
    autoAdvanceInstructions = true,
    autoOpenRuntime = true,
    autoCloseRuntime = true,
    openOnlyWithMarkers = true,
    uiPositions = {},
  }
end

function Migrations.DefaultDatabase()
  return {
    schemaVersion = CURRENT_SCHEMA,
    global = freshGlobal(),
    migration = {
      lastFrom = CURRENT_SCHEMA,
      lastTo = CURRENT_SCHEMA,
      lastStatus = "fresh",
      completedAt = timestamp(),
      retiredLegacyRoutes = 0,
    },
    routeBindings = {},
    lastRouteDungeonIndex = nil,
    backups = {},
  }
end

local function copyDatabaseWithoutBackupPayload(rawDB, maxDepth, maxEntries)
  local source = {}
  for key, value in pairs(rawDB or {}) do if key ~= "backups" then source[key] = value end end
  local copied, copyError = DataUtils.DeepCopy(source, { maxDepth = maxDepth or 14, maxEntries = maxEntries or 30000 })
  if not copied then return nil, copyError end
  copied.backups = {}
  if type(rawDB and rawDB.backups) == "table" and not DataUtils.IsSecret(rawDB.backups) then
    for index = 1, math.min(#rawDB.backups, MAX_BACKUPS) do copied.backups[index] = rawDB.backups[index] end
  end
  return copied
end

local function backupCurrent(rawDB)
  local backup, copyError = copyDatabaseWithoutBackupPayload(rawDB, 14, 30000)
  if not backup then return nil, "backup-failed:"..tostring(copyError) end
  backup.backups = nil
  return {
    createdAt = timestamp(),
    schemaVersion = DataUtils.SafeNumber(rawDB.schemaVersion) or 0,
    data = backup,
  }
end

local function migrateZeroToOne(rawDB)
  rawDB.schemaVersion = 1
  if rawDB.preserveExistingMarkers == nil then rawDB.preserveExistingMarkers = true end
  if rawDB.debug == nil then rawDB.debug = false end
  if rawDB.firstRun == nil then rawDB.firstRun = true end
  if type(rawDB.logs) ~= "table" then rawDB.logs = {} end
  return rawDB
end

local function migrateOneToTwo(rawDB)
  local result = Migrations.DefaultDatabase()
  result.schemaVersion = 2
  result.global.preserveExistingMarkers = rawDB.preserveExistingMarkers ~= false
  result.global.debug = rawDB.debug == true
  result.global.firstRun = rawDB.firstRun ~= false
  if type(rawDB.logs) == "table" then
    local startIndex = math.max(1, #rawDB.logs - 99)
    for index = startIndex, #rawDB.logs do
      local entry = rawDB.logs[index]
      if type(entry) == "table" then
        result.global.logs[#result.global.logs + 1] = {
          time = DataUtils.SafeString(entry.time, 40, true) or "unknown-time",
          level = DataUtils.SafeString(entry.level, 16, true) or "INFO",
          message = DataUtils.SafeString(entry.message, 800, true) or "",
        }
      end
    end
  end
  if type(rawDB.routes) == "table" then
    local routesCopy = DataUtils.DeepCopy(rawDB.routes, { maxDepth = 12, maxEntries = 25000 })
    if routesCopy then result.routes = routesCopy end
  end
  return result
end

local function migrateTwoToThree(rawDB)
  rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
  if rawDB.global.autoAdvanceInstructions == nil then rawDB.global.autoAdvanceInstructions = true end
  if rawDB.global.runtimeLocked == nil then rawDB.global.runtimeLocked = false end
  if type(rawDB.global.uiPositions) ~= "table" then rawDB.global.uiPositions = {} end
  rawDB.schemaVersion = 3
  return rawDB
end

local function migrateThreeToFour(rawDB)
  rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
  if rawDB.global.autoOpenRuntime == nil then rawDB.global.autoOpenRuntime = true end
  if rawDB.global.autoCloseRuntime == nil then rawDB.global.autoCloseRuntime = true end
  if rawDB.global.openOnlyWithMarkers == nil then rawDB.global.openOnlyWithMarkers = true end
  if rawDB.global.warnRouteMismatch == nil then rawDB.global.warnRouteMismatch = true end

  local retired = 0
  if type(rawDB.routes) == "table" then
    for _ in pairs(rawDB.routes) do retired = retired + 1 end
  end
  rawDB.routes = nil
  rawDB.quarantine = nil
  rawDB.global.activeRouteKey = nil
  rawDB.migration = type(rawDB.migration) == "table" and rawDB.migration or {}
  rawDB.migration.retiredLegacyRoutes = retired
  rawDB.schemaVersion = 4
  return rawDB
end

local function migrateFourToFive(rawDB)
  rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
  rawDB.global.executionMode = nil
  rawDB.global.strictValidation = nil
  rawDB.schemaVersion = 5
  return rawDB
end

local function migrateFiveToSix(rawDB)
  rawDB.enemyMetadataCache = nil
  rawDB.schemaVersion = 6
  return rawDB
end


local function migrateSixToSeven(rawDB)
  rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
  rawDB.global.autoOpenRuntime = false
  rawDB.schemaVersion = 7
  return rawDB
end


local function migrateSevenToEight(rawDB)
  rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
  -- Keep the legacy setting enabled for migration/bridge compatibility. Current bulk
  -- execution uses set-if-unmarked for all automatic marker operations.
  rawDB.global.preserveExistingMarkers = true
  rawDB.schemaVersion = 8
  return rawDB
end



local function migrateEightToNine(rawDB)
  rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
  -- rc37 activates the runtime automatically when a usable dungeon session starts.
  -- Users can still disable this later with /mpm autoopen off.
  rawDB.global.autoOpenRuntime = true
  rawDB.schemaVersion = 9
  return rawDB
end

local function migrateNineToTen(rawDB)
  -- rc45 can bind MDTPullMarker to one explicit MDT route. Existing installs
  -- start unbound and keep the rc44 current-route behavior until the user binds.
  rawDB.routeBinding = nil
  rawDB.schemaVersion = 10
  return rawDB
end

local function migrateTenToEleven(rawDB)
  -- rc46 stores one independent route binding per MDT dungeon. Preserve an
  -- existing rc45 binding instead of forcing the user to bind it again.
  rawDB.routeBindings = type(rawDB.routeBindings) == "table" and rawDB.routeBindings or {}
  local legacy = type(rawDB.routeBinding) == "table" and rawDB.routeBinding or nil
  local dungeonIndex = legacy and DataUtils.PositiveInteger(legacy.dungeonIndex, 1000) or nil
  if dungeonIndex then
    rawDB.routeBindings[dungeonIndex] = legacy
    rawDB.lastRouteDungeonIndex = dungeonIndex
  end
  rawDB.routeBinding = nil
  rawDB.schemaVersion = 11
  return rawDB
end

local function migrateElevenToTwelve(rawDB)
  -- These legacy UI preferences no longer control any runtime path: route/dungeon
  -- matching is a mandatory safety invariant and runtime windows are always movable.
  -- Retire the stale keys explicitly instead of carrying dead settings forever.
  rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
  rawDB.global.runtimeLocked = nil
  rawDB.global.warnRouteMismatch = nil
  rawDB.schemaVersion = 12
  return rawDB
end

local migrationSteps = {
  [0] = migrateZeroToOne,
  [1] = migrateOneToTwo,
  [2] = migrateTwoToThree,
  [3] = migrateThreeToFour,
  [4] = migrateFourToFive,
  [5] = migrateFiveToSix,
  [6] = migrateSixToSeven,
  [7] = migrateSevenToEight,
  [8] = migrateEightToNine,
  [9] = migrateNineToTen,
  [10] = migrateTenToEleven,
  [11] = migrateElevenToTwelve,
}

function Migrations.Run(rawDB)
  if rawDB == nil then return Migrations.DefaultDatabase(), { from = nil, to = CURRENT_SCHEMA, status = "fresh", retiredLegacyRoutes = 0 } end
  if type(rawDB) ~= "table" then return nil, "database-not-table" end
  if DataUtils.IsSecret(rawDB) then return nil, "database-secret" end

  local originalVersion = DataUtils.SafeNumber(rawDB.schemaVersion) or 0
  if originalVersion > CURRENT_SCHEMA then return nil, "future-schema" end
  if originalVersion == CURRENT_SCHEMA then
    -- The current schema has a closed active surface. Ignore unknown top-level junk so a
    -- stale/corrupt foreign field cannot exhaust the bounded copy and disable
    -- an otherwise valid installation. Migration backups remain archival.
    local currentSource = {
      schemaVersion = rawDB.schemaVersion,
      global = rawDB.global,
      enemyMetadataCache = rawDB.enemyMetadataCache,
      routeBindings = rawDB.routeBindings,
      lastRouteDungeonIndex = rawDB.lastRouteDungeonIndex,
      migration = rawDB.migration,
      backups = rawDB.backups,
    }
    local currentCopy, copyError = copyDatabaseWithoutBackupPayload(currentSource, 10, 5000)
    if not currentCopy then return nil, "copy-failed:"..tostring(copyError) end
    return currentCopy, {
      from = originalVersion,
      to = CURRENT_SCHEMA,
      status = "unchanged",
      retiredLegacyRoutes = tonumber(currentCopy.migration and currentCopy.migration.retiredLegacyRoutes) or 0,
    }
  end

  local backup, backupError = backupCurrent(rawDB)
  if not backup then return nil, backupError end
  local working, copyError = copyDatabaseWithoutBackupPayload(rawDB, 14, 30000)
  if not working then return nil, "copy-failed:"..tostring(copyError) end

  local version = originalVersion
  while version < CURRENT_SCHEMA do
    local step = migrationSteps[version]
    if not step then return nil, "missing-migration-step:"..tostring(version) end
    local ok, migrated = pcall(step, working)
    if not ok or type(migrated) ~= "table" then return nil, "migration-step-failed:"..tostring(version) end
    working = migrated
    local nextVersion = tonumber(working.schemaVersion)
    if not nextVersion or nextVersion <= version then return nil, "migration-did-not-advance:"..tostring(version) end
    version = nextVersion
  end

  working.backups = type(working.backups) == "table" and working.backups or {}
  table.insert(working.backups, 1, backup)
  while #working.backups > MAX_BACKUPS do table.remove(working.backups) end
  local retired = tonumber(working.migration and working.migration.retiredLegacyRoutes) or 0
  working.migration = {
    lastFrom = originalVersion,
    lastTo = CURRENT_SCHEMA,
    lastStatus = "migrated",
    completedAt = timestamp(),
    retiredLegacyRoutes = retired,
  }
  return working, { from = originalVersion, to = CURRENT_SCHEMA, status = "migrated", retiredLegacyRoutes = retired }
end

Migrations.CurrentSchema = CURRENT_SCHEMA
