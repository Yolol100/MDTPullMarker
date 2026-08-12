local _, Addon = ...

local Database = {}
Addon.Database = Database

local DataUtils = Addon.DataUtils
local Migrations = Addon.Migrations
local Validator = Addon.Validator

local db
local state = {
  initialized = false,
  persistent = false,
  blocked = false,
  lastError = nil,
  migration = nil,
  retiredLegacyRoutes = 0,
}

local VALID_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function normalizePosition(raw)
  if type(raw) ~= "table" or DataUtils.IsSecret(raw) then return nil end
  local point = DataUtils.SafeString(raw.point, 20, true)
  local relativePoint = DataUtils.SafeString(raw.relativePoint, 20, true)
  local x, y = DataUtils.SafeNumber(raw.x), DataUtils.SafeNumber(raw.y)
  if not VALID_POINTS[point or ""] or not VALID_POINTS[relativePoint or ""] then return nil end
  if not x or not y or x ~= x or y ~= y or math.abs(x) > 5000 or math.abs(y) > 5000 then return nil end
  return { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function normalizeUIPositions(raw)
  local result = {}
  if type(raw) ~= "table" or DataUtils.IsSecret(raw) then return result end
  for _, key in ipairs({ "runtime", "configuration" }) do
    local position = normalizePosition(raw[key])
    if position then result[key] = position end
  end
  return result
end

local MAX_METADATA_ENEMIES = 600
local MAX_METADATA_CLONES_PER_ENEMY = 1000

local function exactMetadataName(value)
  if DataUtils.IsSecret(value) or type(value) ~= "string" then return nil end
  local name = DataUtils.Trim(value)
  if not name or name == "" or #name > 1024 then return nil end
  return name
end

local function normalizeEnemyMetadataCache(raw)
  if type(raw) ~= "table" or DataUtils.IsSecret(raw) then return nil end
  local dungeonIndex = DataUtils.PositiveInteger(raw.dungeonIndex)
  local mdtVersion = DataUtils.SafeString(raw.mdtVersion, 40, true)
  local locale = DataUtils.SafeString(raw.locale, 16, true)
  if not dungeonIndex or not mdtVersion or not locale or type(raw.enemies) ~= "table" or DataUtils.IsSecret(raw.enemies) then return nil end
  local enemies, count = {}, 0
  for enemyIndex, rawEnemy in pairs(raw.enemies) do
    enemyIndex = DataUtils.PositiveInteger(enemyIndex)
    if enemyIndex and type(rawEnemy) == "table" and not DataUtils.IsSecret(rawEnemy) then
      local npcID = DataUtils.PositiveInteger(rawEnemy.id or rawEnemy.npcID)
      local name = exactMetadataName(rawEnemy.name)
      local cloneCount = DataUtils.PositiveInteger(rawEnemy.cloneCount, MAX_METADATA_CLONES_PER_ENEMY)
      if npcID and name and cloneCount then
        count = count + 1
        if count > MAX_METADATA_ENEMIES then break end
        enemies[enemyIndex] = { id = npcID, name = name, cloneCount = cloneCount }
      end
    end
  end
  if count == 0 then return nil end
  local dungeonName = exactMetadataName(raw.dungeonName)
  local challengeMapID = DataUtils.PositiveInteger(raw.challengeMapID)
  return {
    dungeonIndex=dungeonIndex,
    dungeonName=dungeonName,
    challengeMapID=challengeMapID,
    mdtVersion=mdtVersion,
    locale=locale,
    targetNamesVerified=raw.targetNamesVerified==true,
    enemies=enemies,
  }
end

local function normalizeRouteBinding(raw)
  if type(raw) ~= "table" or DataUtils.IsSecret(raw) then return nil end
  local routeKey = DataUtils.SafeString(raw.routeKey, 120, true)
  local dungeonIndex = DataUtils.PositiveInteger(raw.dungeonIndex, 1000)
  if not routeKey or routeKey == "" or not dungeonIndex then return nil end
  return {
    routeKey = routeKey,
    presetUID = DataUtils.SafeString(raw.presetUID, 120, true),
    presetName = DataUtils.SafeString(raw.presetName, 240, true),
    presetIndex = DataUtils.PositiveInteger(raw.presetIndex, 1000),
    dungeonIndex = dungeonIndex,
    dungeonName = DataUtils.SafeString(raw.dungeonName, 240, true),
    challengeMapID = DataUtils.PositiveInteger(raw.challengeMapID),
    boundFingerprint = DataUtils.SafeString(raw.boundFingerprint, 120, true),
    mdtVersion = DataUtils.SafeString(raw.mdtVersion, 40, true),
  }
end


local function normalizeRouteBindings(raw)
  local result = {}
  if type(raw) ~= "table" or DataUtils.IsSecret(raw) then return result end
  local count = 0
  for rawDungeonIndex, rawBinding in pairs(raw) do
    local dungeonIndex = DataUtils.PositiveInteger(rawDungeonIndex, 1000)
    local binding = normalizeRouteBinding(rawBinding)
    if dungeonIndex and binding and binding.dungeonIndex == dungeonIndex then
      count = count + 1
      if count > 1000 then break end
      result[dungeonIndex] = binding
    end
  end
  return result
end

local function normalizeGlobal(raw)
  raw = type(raw) == "table" and not DataUtils.IsSecret(raw) and raw or {}
  local result = {
    preserveExistingMarkers = true,
    debug = raw.debug == true,
    firstRun = raw.firstRun ~= false,
    logs = {},
    autoAdvanceInstructions = raw.autoAdvanceInstructions ~= false,
    autoOpenRuntime = raw.autoOpenRuntime ~= false,
    autoCloseRuntime = raw.autoCloseRuntime ~= false,
    openOnlyWithMarkers = raw.openOnlyWithMarkers ~= false,
    uiPositions = normalizeUIPositions(raw.uiPositions),
  }
  if type(raw.logs) == "table" and not DataUtils.IsSecret(raw.logs) then
    local start = math.max(1, #raw.logs - (Validator.MaxLogs - 1))
    for index = start, #raw.logs do
      local entry = raw.logs[index]
      if type(entry) == "table" and not DataUtils.IsSecret(entry) then
        result.logs[#result.logs + 1] = {
          time = DataUtils.SafeString(entry.time, 40, true) or "unknown-time",
          level = DataUtils.SafeString(entry.level, 16, true) or "INFO",
          message = DataUtils.SafeString(entry.message, 800, true) or "",
        }
      end
    end
  end
  return result
end

local function normalizeDatabase(candidate)
  candidate = type(candidate) == "table" and candidate or {}
  candidate.schemaVersion = Migrations.CurrentSchema
  candidate.global = normalizeGlobal(candidate.global)
  candidate.enemyMetadataCache = normalizeEnemyMetadataCache(candidate.enemyMetadataCache)
  candidate.routeBindings = normalizeRouteBindings(candidate.routeBindings)
  candidate.lastRouteDungeonIndex = DataUtils.PositiveInteger(candidate.lastRouteDungeonIndex, 1000)
  if candidate.lastRouteDungeonIndex and not candidate.routeBindings[candidate.lastRouteDungeonIndex] then
    candidate.lastRouteDungeonIndex = nil
  end
  candidate.routeBinding = nil
  candidate.routes = nil
  candidate.quarantine = nil
  candidate.backups = type(candidate.backups) == "table" and candidate.backups or {}
  while #candidate.backups > Validator.MaxBackups do table.remove(candidate.backups) end
  candidate.migration = type(candidate.migration) == "table" and candidate.migration or {}
  return candidate
end

function Database.Initialize(rawDB)
  state.initialized = false
  state.persistent = false
  state.blocked = false
  state.lastError = nil
  state.migration = nil
  state.retiredLegacyRoutes = 0
  if rawDB == nil then rawDB = _G.MDTPullMarkerDB end

  local migrated, migrationOrError = Migrations.Run(rawDB)
  if not migrated then
    state.blocked = migrationOrError == "future-schema"
    state.lastError = migrationOrError
    db = Migrations.DefaultDatabase()
    state.initialized = true
    return false, migrationOrError
  end

  local candidate = normalizeDatabase(migrated)
  local valid, findings = Validator.ValidateDatabase(candidate, Migrations.CurrentSchema)
  if not valid then
    state.blocked = false
    state.lastError = "database-validation-failed"
    state.findings = findings
    db = Migrations.DefaultDatabase()
    state.initialized = true
    return false, state.lastError
  end

  db = candidate
  _G.MDTPullMarkerDB = db
  state.initialized = true
  state.persistent = true
  state.migration = migrationOrError
  state.retiredLegacyRoutes = tonumber(migrationOrError and migrationOrError.retiredLegacyRoutes) or 0
  state.findings = findings
  return true, migrationOrError
end

function Database.Get() return db end
function Database.GetGlobal() return db and db.global or nil end
function Database.GetState()
  return {
    initialized = state.initialized,
    persistent = state.persistent,
    blocked = state.blocked,
    lastError = state.lastError,
    migration = DataUtils.DeepCopy(state.migration),
    retiredLegacyRoutes = state.retiredLegacyRoutes,
    findings = DataUtils.DeepCopy(state.findings or {}),
    mode = state.blocked and "blocked" or (state.persistent and "persistent" or "memory-only"),
  }
end

function Database.Transaction(context, callback)
  if not db or state.blocked then return nil, "database-unavailable" end
  if type(callback) ~= "function" then return nil, "callback-not-function" end
  local transactionSource = {}
  for key, value in pairs(db) do if key ~= "backups" then transactionSource[key] = value end end
  local working, copyError = DataUtils.DeepCopy(transactionSource, { maxDepth = 10, maxEntries = 5000 })
  if not working then return nil, "transaction-copy-failed:"..tostring(copyError) end
  working.backups = {}
  for index = 1, math.min(#(db.backups or {}), Validator.MaxBackups) do working.backups[index] = db.backups[index] end
  local callbackResult, callbackError
  local ok, runtimeError = pcall(function() callbackResult, callbackError = callback(working) end)
  if not ok then return nil, "transaction-runtime-error:"..tostring(runtimeError) end
  if callbackResult == nil and callbackError then return nil, callbackError end
  working = normalizeDatabase(working)
  local valid, findings = Validator.ValidateDatabase(working, Migrations.CurrentSchema)
  if not valid then return nil, "transaction-validation-failed", findings end
  db = working
  if state.persistent then _G.MDTPullMarkerDB = db end
  return callbackResult == nil and true or callbackResult
end

function Database.GetRouteBinding(dungeonIndex)
  if not db then return nil end
  dungeonIndex = DataUtils.PositiveInteger(dungeonIndex, 1000) or DataUtils.PositiveInteger(db.lastRouteDungeonIndex, 1000)
  local binding = dungeonIndex and db.routeBindings and db.routeBindings[dungeonIndex] or nil
  return binding and DataUtils.DeepCopy(binding) or nil
end

function Database.GetRouteBindings()
  return db and DataUtils.DeepCopy(db.routeBindings or {}, { maxDepth = 4, maxEntries = 5000 }) or {}
end

function Database.FindRouteBindingByChallengeMapID(challengeMapID)
  challengeMapID = DataUtils.PositiveInteger(challengeMapID)
  if not db or not challengeMapID then return nil end
  local match
  for dungeonIndex, binding in pairs(db.routeBindings or {}) do
    if tonumber(binding.challengeMapID) == challengeMapID then
      if match then return nil, "route-binding-map-ambiguous" end
      match = { dungeonIndex = dungeonIndex, binding = binding }
    end
  end
  if not match then return nil, "route-binding-map-not-found" end
  return DataUtils.DeepCopy(match.binding), match.dungeonIndex
end

function Database.SetRouteBinding(rawBinding)
  local binding = normalizeRouteBinding(rawBinding)
  if not binding then return nil, "invalid-route-binding" end
  return Database.Transaction("set-route-binding", function(working)
    working.routeBindings = type(working.routeBindings) == "table" and working.routeBindings or {}
    if binding.challengeMapID then
      for dungeonIndex, existing in pairs(working.routeBindings) do
        if tonumber(dungeonIndex) ~= binding.dungeonIndex and type(existing) == "table"
          and tonumber(existing.challengeMapID) == binding.challengeMapID then
          return nil, "route-binding-map-conflict"
        end
      end
    end
    working.routeBindings[binding.dungeonIndex] = binding
    working.lastRouteDungeonIndex = binding.dungeonIndex
    return true
  end)
end

function Database.ClearRouteBinding(dungeonIndex)
  dungeonIndex = DataUtils.PositiveInteger(dungeonIndex, 1000) or (db and DataUtils.PositiveInteger(db.lastRouteDungeonIndex, 1000))
  if not dungeonIndex then return nil, "route-binding-dungeon-required" end
  return Database.Transaction("clear-route-binding", function(working)
    working.routeBindings = type(working.routeBindings) == "table" and working.routeBindings or {}
    working.routeBindings[dungeonIndex] = nil
    if tonumber(working.lastRouteDungeonIndex) == dungeonIndex then
      working.lastRouteDungeonIndex = nil
      for candidate in pairs(working.routeBindings) do
        working.lastRouteDungeonIndex = DataUtils.PositiveInteger(candidate, 1000)
        if working.lastRouteDungeonIndex then break end
      end
    end
    return true
  end)
end

function Database.SetGlobal(field, value)
  local allowed = {
    preserveExistingMarkers = "boolean", debug = "boolean", firstRun = "boolean",
    autoAdvanceInstructions = "boolean",
    autoOpenRuntime = "boolean", autoCloseRuntime = "boolean",
    openOnlyWithMarkers = "boolean",
  }
  local expected = allowed[field]
  if not expected then return nil, "unsupported-global-setting" end
  if expected == "boolean" and type(value) ~= "boolean" then return nil, "invalid-global-setting" end
  if field == "preserveExistingMarkers" and value ~= true then
    return nil, "preserve-existing-required-for-safe-bulk-macros"
  end
  return Database.Transaction("set-global:"..tostring(field), function(working)
    working.global[field] = value
    return true
  end)
end

function Database.GetUIPosition(frameKey)
  if frameKey ~= "runtime" and frameKey ~= "configuration" then return nil end
  local position = db and db.global and db.global.uiPositions and db.global.uiPositions[frameKey]
  return position and DataUtils.DeepCopy(position) or nil
end

function Database.SaveUIPosition(frameKey, rawPosition)
  if frameKey ~= "runtime" and frameKey ~= "configuration" then return nil, "invalid-ui-frame" end
  local position = normalizePosition(rawPosition)
  if not position then return nil, "invalid-ui-position" end
  return Database.Transaction("save-ui-position", function(working)
    working.global.uiPositions = type(working.global.uiPositions) == "table" and working.global.uiPositions or {}
    working.global.uiPositions[frameKey] = position
    return true
  end)
end

function Database.ClearLogs()
  return Database.Transaction("clear-logs", function(working) working.global.logs = {} return true end)
end

function Database.ResetUIPositions()
  return Database.Transaction("reset-ui-positions", function(working)
    working.global.uiPositions = {}
    return true
  end)
end


function Database.GetEnemyMetadataCache()
  local cache = db and db.enemyMetadataCache
  return cache and DataUtils.DeepCopy(cache, { maxDepth = 6, maxEntries = 2500 }) or nil
end

function Database.SaveEnemyMetadataCache(rawCache)
  local normalized = normalizeEnemyMetadataCache(rawCache)
  if not normalized then return nil, "invalid-enemy-metadata-cache" end
  return Database.Transaction("save-enemy-metadata-cache", function(working) working.enemyMetadataCache = normalized return true end)
end
