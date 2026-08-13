local _, Addon = ...

local Validator = {}
Addon.Validator = Validator

local DataUtils = Addon.DataUtils
local MAX_LOGS = 100
local MAX_BACKUPS = 2
local MAX_METADATA_ENEMIES = 600

local function add(findings, severity, code, path, detail)
  findings[#findings + 1] = { severity = severity, code = code, path = path, detail = detail }
end

local function inspect(value, path, depth, seen, findings)
  if path:match("^database/backups/%d+") then return end
  if DataUtils.IsSecret(value) then add(findings, "error", "secret-database-value", path) return end
  if depth > 10 then add(findings, "error", "database-max-depth", path) return end
  local valueType = type(value)
  if valueType == "function" or valueType == "userdata" or valueType == "thread" then
    add(findings, "error", "unsupported-database-type", path, valueType)
    return
  end
  if valueType ~= "table" then return end
  if seen[value] then add(findings, "error", "database-cycle", path) return end
  seen[value] = true
  for key, child in pairs(value) do
    if DataUtils.IsSecret(key) then
      add(findings, "error", "secret-database-key", path)
    else
      inspect(child, path.."/"..tostring(key), depth + 1, seen, findings)
    end
  end
  seen[value] = nil
end

function Validator.ValidateDatabase(rawDB, expectedSchema)
  local findings = {}
  if type(rawDB) ~= "table" or DataUtils.IsSecret(rawDB) then
    add(findings, "error", "database-not-table", "database")
    return false, findings
  end
  if DataUtils.PositiveInteger(rawDB.schemaVersion) ~= expectedSchema then
    local schemaDetail = DataUtils.IsSecret(rawDB.schemaVersion) and "<secret>" or tostring(rawDB.schemaVersion)
    add(findings, "error", "schema-version-mismatch", "database.schemaVersion", schemaDetail)
  end
  if rawDB.routes ~= nil then add(findings, "error", "legacy-routes-not-retired", "database.routes") end
  if type(rawDB.global) ~= "table" then
    add(findings, "error", "global-settings-not-table", "database.global")
  else
    if type(rawDB.global.logs) ~= "table" then
      add(findings, "error", "logs-not-table", "database.global.logs")
    elseif #rawDB.global.logs > MAX_LOGS then
      add(findings, "error", "too-many-logs", "database.global.logs", tostring(#rawDB.global.logs))
    end
    for _, field in ipairs({
      "preserveExistingMarkers", "debug", "firstRun",
      "autoAdvanceInstructions", "autoOpenRuntime",
      "autoCloseRuntime", "openOnlyWithMarkers",
    }) do
      if type(rawDB.global[field]) ~= "boolean" then
        add(findings, "error", "invalid-boolean-setting", "database.global."..field)
      end
    end
  end
  if rawDB.routeBinding ~= nil then
    add(findings, "error", "legacy-route-binding-not-retired", "database.routeBinding")
  end
  if type(rawDB.routeBindings) ~= "table" then
    add(findings, "error", "route-bindings-not-table", "database.routeBindings")
  else
    local bindingCount = 0
    for rawDungeonIndex, binding in pairs(rawDB.routeBindings) do
      bindingCount = bindingCount + 1
      if bindingCount > 1000 then
        add(findings, "error", "too-many-route-bindings", "database.routeBindings")
        break
      end
      local dungeonIndex = DataUtils.PositiveInteger(rawDungeonIndex, 1000)
      local basePath = "database.routeBindings/"..tostring(rawDungeonIndex)
      if not dungeonIndex then
        add(findings, "error", "invalid-route-binding-index", basePath)
      elseif type(binding) ~= "table" then
        add(findings, "error", "route-binding-not-table", basePath)
      else
        if type(binding.routeKey) ~= "string" or binding.routeKey == "" or #binding.routeKey > 120 then
          add(findings, "error", "invalid-route-binding-key", basePath.."/routeKey")
        end
        if DataUtils.PositiveInteger(binding.dungeonIndex, 1000) ~= dungeonIndex then
          add(findings, "error", "invalid-route-binding-dungeon", basePath.."/dungeonIndex")
        end
        for _, field in ipairs({ "presetUID", "presetName", "dungeonName", "boundFingerprint", "mdtVersion" }) do
          local value = binding[field]
          if value ~= nil and type(value) ~= "string" then
            add(findings, "error", "invalid-route-binding-field", basePath.."/"..field)
          end
        end
        if binding.presetIndex ~= nil and not DataUtils.PositiveInteger(binding.presetIndex, 1000) then
          add(findings, "error", "invalid-route-binding-preset-index", basePath.."/presetIndex")
        end
        if binding.challengeMapID ~= nil and not DataUtils.PositiveInteger(binding.challengeMapID) then
          add(findings, "error", "invalid-route-binding-map", basePath.."/challengeMapID")
        end
      end
    end
  end
  if rawDB.lastRouteDungeonIndex ~= nil then
    local last = DataUtils.PositiveInteger(rawDB.lastRouteDungeonIndex, 1000)
    if not last or type(rawDB.routeBindings) ~= "table" or rawDB.routeBindings[last] == nil then
      add(findings, "error", "invalid-last-route-dungeon", "database.lastRouteDungeonIndex")
    end
  end
  if rawDB.enemyMetadataCache ~= nil then
    local cache = rawDB.enemyMetadataCache
    if type(cache) ~= "table" then add(findings, "error", "enemy-metadata-cache-not-table", "database.enemyMetadataCache")
    else
      if not DataUtils.PositiveInteger(cache.dungeonIndex) then add(findings, "error", "invalid-enemy-metadata-cache-dungeon", "database.enemyMetadataCache.dungeonIndex") end
      if type(cache.mdtVersion) ~= "string" or cache.mdtVersion == "" then add(findings, "error", "invalid-enemy-metadata-cache-version", "database.enemyMetadataCache.mdtVersion") end
      if type(cache.locale) ~= "string" or cache.locale == "" then add(findings, "error", "invalid-enemy-metadata-cache-locale", "database.enemyMetadataCache.locale") end
      if cache.dungeonName ~= nil and (type(cache.dungeonName) ~= "string" or cache.dungeonName == "" or #cache.dungeonName > 1024) then add(findings, "error", "invalid-enemy-metadata-cache-dungeon-name", "database.enemyMetadataCache.dungeonName") end
      if cache.challengeMapID ~= nil and not DataUtils.PositiveInteger(cache.challengeMapID) then add(findings, "error", "invalid-enemy-metadata-cache-challenge-map", "database.enemyMetadataCache.challengeMapID") end
      if type(cache.targetNamesVerified) ~= "boolean" then add(findings, "error", "invalid-enemy-metadata-cache-verification", "database.enemyMetadataCache.targetNamesVerified") end
      if type(cache.enemies) ~= "table" then add(findings, "error", "enemy-metadata-cache-enemies-not-table", "database.enemyMetadataCache.enemies")
      else
        local enemyCount = 0
        for enemyIndex, enemy in pairs(cache.enemies) do
          enemyCount = enemyCount + 1
          if enemyCount > MAX_METADATA_ENEMIES then add(findings, "error", "too-many-enemy-metadata-cache-entries", "database.enemyMetadataCache.enemies") break end
          if not DataUtils.PositiveInteger(enemyIndex) or type(enemy) ~= "table" or not DataUtils.PositiveInteger(enemy.id) or type(enemy.name) ~= "string" or not DataUtils.PositiveInteger(enemy.cloneCount) then
            add(findings, "error", "invalid-enemy-metadata-cache-entry", "database.enemyMetadataCache.enemies/"..tostring(enemyIndex))
          end
        end
      end
    end
  end
  if type(rawDB.backups) ~= "table" then
    add(findings, "error", "backups-not-table", "database.backups")
  elseif #rawDB.backups > MAX_BACKUPS then
    add(findings, "error", "too-many-backups", "database.backups", tostring(#rawDB.backups))
  end
  inspect(rawDB, "database", 1, {}, findings)
  for _, finding in ipairs(findings) do if finding.severity == "error" then return false, findings end end
  return true, findings
end

function Validator.Summarize(findings)
  local result = { errors = 0, warnings = 0, info = 0 }
  for _, finding in ipairs(findings or {}) do
    if finding.severity == "error" then result.errors = result.errors + 1
    elseif finding.severity == "warning" then result.warnings = result.warnings + 1
    else result.info = result.info + 1 end
  end
  return result
end

Validator.MaxLogs = MAX_LOGS
Validator.MaxBackups = MAX_BACKUPS
Validator.MaxMetadataEnemies = MAX_METADATA_ENEMIES
