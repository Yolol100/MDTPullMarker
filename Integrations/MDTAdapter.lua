local _, Addon = ...

local Adapter = {}
Addon.MDT = Adapter
Addon.Backend = Adapter -- compatibility alias

local DataUtils = Addon.DataUtils

local MDT_ADDON = "MythicDungeonTools"
local MDT_UI_ADDON = "MythicDungeonTools_UI"
local TESTED_MIN = { 6, 1, 17 }
local TESTED_MAX_EXCLUSIVE = { 6, 3, 0 }
local VERIFIED_SOURCE_VERSIONS = {
  ["6.1.20"] = true,
  ["6.2.0-alpha5"] = true,
  ["6.2.1"] = true,
  ["6.2.2"] = true,
  ["6.2.4"] = true,
}

local state = {
  installed = false,
  loaded = false,
  uiLoaded = false,
  version = nil,
  versionStatus = "unknown",
  mode = "missing",
  compatibility = "unavailable",
  lastError = nil,
  warnings = {},
  snapshot = nil,
  activeBinding = nil,
  lastRefreshReason = nil,
}

local initializerRegistered = false
local enemyHookInstalled = false
local enemyCaptureRefreshScheduled = false
local enemyCaptureSerial = 0
local capturedEnemyData = {}
local capturedActiveDungeonIndex
local capturedTargetNamesVerified = false
local routeWatchTicker
local routeWatchSignature
local routeMutationHooksInstalled = false
local routeMutationRefreshScheduled = false
local routeMutationObservedInCombat = false

local MAX_ASSIGNMENT_ENEMIES = 500
local MAX_ASSIGNMENT_CLONES_PER_ENEMY = 1000
local MAX_ASSIGNMENT_TOTAL = 20000
local MAX_ASSIGNMENT_SCAN_MULTIPLIER = 4

local function safeCall(callable, ...)
  if type(callable) ~= "function" then return nil, "unavailable" end
  local ok, first, second = pcall(callable, ...)
  if not ok then return nil, tostring(first) end
  if Addon.IsSecret and Addon.IsSecret(first) then return nil, "secret" end
  if Addon.IsSecret and Addon.IsSecret(second) then second = nil end
  return first, second
end

local function getMetadata(field)
  if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
    return safeCall(C_AddOns.GetAddOnMetadata, MDT_ADDON, field)
  end
  if type(GetAddOnMetadata) == "function" then return safeCall(GetAddOnMetadata, MDT_ADDON, field) end
end

local function isLoaded(addon)
  if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
    local first, second = safeCall(C_AddOns.IsAddOnLoaded, addon)
    if second == nil and type(first) == "boolean" then return first end
    if type(second) == "boolean" then return second end
  end
  if type(IsAddOnLoaded) == "function" then return safeCall(IsAddOnLoaded, addon) == true end
  return false
end

local function parseVersion(raw)
  if type(raw) ~= "string" then return nil end
  local major, minor, patch, suffix = raw:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
  if not major then return nil end
  return {
    raw = raw,
    major = tonumber(major),
    minor = tonumber(minor),
    patch = tonumber(patch),
    suffix = suffix ~= "" and suffix or nil,
  }
end

local function compareVersion(version, tuple)
  if not version then return nil end
  local values = { version.major, version.minor, version.patch }
  for index = 1, 3 do
    if values[index] < tuple[index] then return -1 end
    if values[index] > tuple[index] then return 1 end
  end
  return 0
end

local function classifyVersion(version)
  if not version then return "unknown" end
  if compareVersion(version, TESTED_MIN) < 0 then return "too-old" end
  if compareVersion(version, TESTED_MAX_EXCLUSIVE) >= 0 then return "untested-newer" end
  if VERIFIED_SOURCE_VERSIONS[version.raw] then return "verified-source" end
  return "compatible-range"
end

local function resetState(reason)
  state.installed = false
  state.loaded = false
  state.uiLoaded = false
  state.version = nil
  state.versionStatus = "unknown"
  state.mode = "missing"
  state.compatibility = "unavailable"
  state.lastError = nil
  state.warnings = {}
  state.snapshot = nil
  state.activeBinding = nil
  state.lastRefreshReason = reason
end

local function addStateWarning(code, detail)
  state.warnings[#state.warnings + 1] = { code = code, detail = detail }
end

local function getClientLocale()
  if type(GetLocale) == "function" then
    local locale = safeCall(GetLocale)
    locale = DataUtils.ValidatedString and DataUtils.ValidatedString(locale, 16, true)
      or DataUtils.SafeString(locale, 16, true)
    if locale then return locale end
  end
  return "unknown"
end

local function sourceNamesMatchClientLocale(locale)
  return locale == "enUS" or locale == "enGB"
end

local function localeStatus(verified)
  return verified and "verified-client-locale" or "unverified-source-locale"
end

local function normalizeDungeonName(value)
  return DataUtils.NormalizeName(value)
end

local function loadMDTUIForRouteData()
  if isLoaded(MDT_UI_ADDON) then state.uiLoaded = true return true end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "in-combat" end
  local loaded, loadError
  if type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" then
    loaded, loadError = safeCall(C_AddOns.LoadAddOn, MDT_UI_ADDON)
  elseif type(LoadAddOn) == "function" then
    loaded, loadError = safeCall(LoadAddOn, MDT_UI_ADDON)
  else
    return nil, "mdt-ui-loader-unavailable"
  end
  state.uiLoaded = isLoaded(MDT_UI_ADDON)
  if loaded == true or state.uiLoaded then return true end
  return nil, loadError or "mdt-ui-load-failed"
end

local function resolveChallengeMapID(dungeonName)
  local wanted = normalizeDungeonName(dungeonName)
  if not wanted or type(C_ChallengeMode) ~= "table"
    or type(C_ChallengeMode.GetMapTable) ~= "function"
    or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
    return nil
  end
  local mapIDs = safeCall(C_ChallengeMode.GetMapTable)
  if type(mapIDs) ~= "table" or (Addon.IsSecret and Addon.IsSecret(mapIDs)) then return nil end
  for _, rawMapID in ipairs(mapIDs) do
    local mapID = DataUtils.PositiveInteger(rawMapID)
    if mapID then
      local name = safeCall(C_ChallengeMode.GetMapUIInfo, mapID)
      if normalizeDungeonName(name) == wanted then return mapID end
    end
  end
end

local function activeChallengeMapID()
  if type(C_ChallengeMode) ~= "table" or type(C_ChallengeMode.GetActiveChallengeMapID) ~= "function" then return nil end
  return DataUtils.PositiveInteger(safeCall(C_ChallengeMode.GetActiveChallengeMapID))
end

local function challengeMapName(mapID)
  mapID = DataUtils.PositiveInteger(mapID)
  if not mapID or type(C_ChallengeMode) ~= "table" or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then return nil end
  return DataUtils.SafeString(safeCall(C_ChallengeMode.GetMapUIInfo, mapID), 1024, true)
end

local function currentPresetFromDB(db)
  if type(db) ~= "table" or DataUtils.IsSecret(db) then return nil, "missing-db" end
  local dungeonIndex = DataUtils.PositiveInteger(db.currentDungeonIdx)
  if not dungeonIndex or type(db.presets) ~= "table" or DataUtils.IsSecret(db.presets)
    or type(db.currentPreset) ~= "table" or DataUtils.IsSecret(db.currentPreset) then
    return nil, "route-db-not-ready"
  end
  local presetIndex = DataUtils.PositiveInteger(db.currentPreset[dungeonIndex])
  local dungeonPresets = db.presets[dungeonIndex]
  local preset = type(dungeonPresets) == "table" and not DataUtils.IsSecret(dungeonPresets)
    and presetIndex and dungeonPresets[presetIndex] or nil
  if type(preset) ~= "table" or DataUtils.IsSecret(preset) then return nil, "active-preset-missing" end
  return preset, nil, dungeonIndex, presetIndex
end

local function currentDungeonIndexFromAPI(api)
  if type(api) ~= "table" or type(api.GetDB) ~= "function" then return nil end
  local db = safeCall(api.GetDB, api)
  return type(db) == "table" and DataUtils.PositiveInteger(db.currentDungeonIdx) or nil
end

local function invalidateExecution(reason)
  routeWatchSignature = nil
  if Addon.MarkerExecutor and type(Addon.MarkerExecutor.InvalidateExecution) == "function" then
    Addon.MarkerExecutor:InvalidateExecution(reason or "mdt-route-mutated")
  end
end

local function buildCapturedMetadataCache()
  local dungeonIndex = capturedActiveDungeonIndex
  local dungeon = dungeonIndex and capturedEnemyData[dungeonIndex] or nil
  if type(dungeon) ~= "table" or next(dungeon) == nil then return nil end
  local enemies = {}
  for rawEnemyIndex, enemy in pairs(dungeon) do
    local enemyIndex = DataUtils.PositiveInteger(rawEnemyIndex)
    if enemyIndex and type(enemy) == "table" and not DataUtils.IsSecret(enemy) then
      local npcID = DataUtils.PositiveInteger(enemy.id or enemy.npcID)
      local name = type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
      if name and (name == "" or #name > 1024) then name = nil end
      local cloneCount = 0
      if type(enemy.clones) == "table" and not DataUtils.IsSecret(enemy.clones) then
        for cloneIndex in pairs(enemy.clones) do
          if DataUtils.PositiveInteger(cloneIndex) then cloneCount = cloneCount + 1 end
          if cloneCount >= 1000 then break end
        end
      end
      if npcID and name and cloneCount > 0 then
        enemies[enemyIndex] = { id = npcID, name = name, cloneCount = cloneCount }
      end
    end
  end
  if next(enemies) == nil then return nil end
  local snapshot = state.snapshot
  return {
    dungeonIndex = dungeonIndex,
    dungeonName = snapshot and DataUtils.SafeString(snapshot.dungeonName, 1024, true) or nil,
    challengeMapID = snapshot and DataUtils.PositiveInteger(snapshot.challengeMapID) or nil,
    mdtVersion = DataUtils.ValidatedString and DataUtils.ValidatedString(state.version or getMetadata("Version"), 40, true)
      or DataUtils.SafeString(state.version or getMetadata("Version"), 40, true),
    locale = getClientLocale(),
    targetNamesVerified = capturedTargetNamesVerified == true,
    enemies = enemies,
  }
end

local function persistCapturedMetadataCache()
  if not (Addon.Database and type(Addon.Database.SaveEnemyMetadataCache) == "function") then return end
  local cache = buildCapturedMetadataCache()
  if not cache or not cache.mdtVersion then return end
  local saved, saveError = Addon.Database.SaveEnemyMetadataCache(cache)
  if not saved and Addon.Log then
    Addon.Log("WARN", "MDT enemy metadata cache was not saved: "..tostring(saveError), false)
  end
end

local function matchingCachedEnemyData(dungeonIndex)
  if not (Addon.Database and type(Addon.Database.GetEnemyMetadataCache) == "function") then return nil end
  local cache = Addon.Database.GetEnemyMetadataCache()
  if type(cache) ~= "table" then return nil end
  if DataUtils.PositiveInteger(cache.dungeonIndex) ~= dungeonIndex then return nil end
  if tostring(cache.mdtVersion or "") ~= tostring(state.version or "") then return nil end
  if tostring(cache.locale or "") ~= getClientLocale() then return nil end
  if type(cache.enemies) ~= "table" or next(cache.enemies) == nil then return nil end
  return cache.enemies, cache.targetNamesVerified == true, cache.dungeonName, cache.challengeMapID
end

local function persistCachedDungeonIdentity(dungeonIndex, dungeonName, challengeMapID)
  if not (Addon.Database and type(Addon.Database.GetEnemyMetadataCache) == "function"
    and type(Addon.Database.SaveEnemyMetadataCache) == "function") then return end
  local cache = Addon.Database.GetEnemyMetadataCache()
  if type(cache) ~= "table" or DataUtils.PositiveInteger(cache.dungeonIndex) ~= dungeonIndex then return end
  if tostring(cache.mdtVersion or "") ~= tostring(state.version or "") or tostring(cache.locale or "") ~= getClientLocale() then return end
  dungeonName = DataUtils.SafeString(dungeonName, 1024, true)
  challengeMapID = DataUtils.PositiveInteger(challengeMapID)
  if cache.dungeonName == dungeonName and DataUtils.PositiveInteger(cache.challengeMapID) == challengeMapID then return end
  if dungeonName then cache.dungeonName = dungeonName end
  if challengeMapID then cache.challengeMapID = challengeMapID end
  Addon.Database.SaveEnemyMetadataCache(cache)
end

local function scheduleCapturedMetadataRefresh()
  if enemyCaptureRefreshScheduled then return end
  enemyCaptureRefreshScheduled = true
  local scheduledSerial = enemyCaptureSerial
  local function refresh()
    enemyCaptureRefreshScheduled = false
    if scheduledSerial ~= enemyCaptureSerial then
      scheduleCapturedMetadataRefresh()
      return
    end
    persistCapturedMetadataCache()
    Adapter:Refresh("mdt-enemy-metadata-captured")
    if Addon.RuntimeController and type(Addon.RuntimeController.Refresh) == "function" then
      Addon.RuntimeController:Refresh("mdt-enemy-metadata-captured", true)
    end
    if Addon.ConfigurationUI and Addon.ConfigurationUI.HasViews and Addon.ConfigurationUI:HasViews() then
      Addon.ConfigurationUI:Refresh()
    end
    if Addon.RuntimeFrame and Addon.RuntimeFrame.IsOpen and Addon.RuntimeFrame:IsOpen() then
      Addon.RuntimeFrame:Refresh()
    end
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0.2, refresh) else refresh() end
end

local function captureEnemyMetadata(frame, data, clone)
  if type(frame) ~= "table" and type(frame) ~= "userdata" then return end
  if type(data) ~= "table" or DataUtils.IsSecret(data) or type(clone) ~= "table" or DataUtils.IsSecret(clone) then return end
  local api = type(_G.MythicDungeonToolsAPI) == "table" and _G.MythicDungeonToolsAPI or nil
  local dungeonIndex = currentDungeonIndexFromAPI(api)
  local enemyIndex = DataUtils.PositiveInteger(frame.enemyIdx)
  local cloneIndex = DataUtils.PositiveInteger(frame.cloneIdx)
  local npcID = DataUtils.PositiveInteger(data.id or data.npcID)
  if not dungeonIndex or not enemyIndex or not cloneIndex or not npcID then return end

  -- Any redraw may reflect a route/marker mutation. Park managed execution before
  -- the debounced rebuild so a previously generated body cannot remain authoritative.
  invalidateExecution("mdt-enemy-view-mutated")

  if capturedActiveDungeonIndex ~= dungeonIndex then
    capturedEnemyData = {}
    capturedActiveDungeonIndex = dungeonIndex
    capturedTargetNamesVerified = sourceNamesMatchClientLocale(getClientLocale())
  end
  local dungeon = capturedEnemyData[dungeonIndex]
  if type(dungeon) ~= "table" then dungeon = {} capturedEnemyData[dungeonIndex] = dungeon end
  local enemy = dungeon[enemyIndex]
  if type(enemy) ~= "table" then enemy = { clones = {} } dungeon[enemyIndex] = enemy end
  enemy.id = npcID
  local targetName = type(data.name) == "string" and data.name or nil
  if not sourceNamesMatchClientLocale(getClientLocale()) then capturedTargetNamesVerified = false end
  enemy.name = targetName or enemy.name
  enemy.count = DataUtils.SafeNumber(data.count) or enemy.count
  enemy.health = DataUtils.SafeNumber(data.health or data.baseHealth) or enemy.health
  enemy.displayId = DataUtils.PositiveInteger(data.displayId or data.displayID) or enemy.displayId
  enemy.isBoss = data.isBoss == true
  enemy.clones = type(enemy.clones) == "table" and enemy.clones or {}
  local sourceClones = type(data.clones) == "table" and not DataUtils.IsSecret(data.clones) and data.clones or nil
  if sourceClones then
    local copied, scanned = 0, 0
    for rawCloneIndex, sourceClone in pairs(sourceClones) do
      scanned = scanned + 1
      if scanned > MAX_ASSIGNMENT_CLONES_PER_ENEMY * MAX_ASSIGNMENT_SCAN_MULTIPLIER then break end
      local sourceCloneIndex = DataUtils.PositiveInteger(rawCloneIndex)
      if sourceCloneIndex and type(sourceClone) == "table" and not DataUtils.IsSecret(sourceClone) then
        enemy.clones[sourceCloneIndex] = {
          x = DataUtils.SafeNumber(sourceClone.x),
          y = DataUtils.SafeNumber(sourceClone.y),
          sublevel = DataUtils.PositiveInteger(sourceClone.sublevel),
          scale = DataUtils.SafeNumber(sourceClone.scale),
        }
        copied = copied + 1
        if copied >= 1000 then break end
      end
    end
  else
    enemy.clones[cloneIndex] = {
      x = DataUtils.SafeNumber(clone.x),
      y = DataUtils.SafeNumber(clone.y),
      sublevel = DataUtils.PositiveInteger(clone.sublevel),
      scale = DataUtils.SafeNumber(clone.scale),
    }
  end
  enemyCaptureSerial = enemyCaptureSerial + 1
  scheduleCapturedMetadataRefresh()
end

local function installEnemyMetadataHook()
  if enemyHookInstalled then return true end
  local mixin = _G.MDTDungeonEnemyMixin
  if type(mixin) ~= "table" or type(mixin.SetUp) ~= "function" or type(hooksecurefunc) ~= "function" then
    return nil, "mdt-enemy-hook-unavailable"
  end
  local ok, hookError = pcall(hooksecurefunc, mixin, "SetUp", captureEnemyMetadata)
  if not ok then return nil, "mdt-enemy-hook-failed:"..tostring(hookError) end
  enemyHookInstalled = true
  return true
end

local function markedLegacyNamesVerified(preset, enemyData, locale, localeTable)
  if sourceNamesMatchClientLocale(locale) then return true end
  if type(localeTable) ~= "table" or DataUtils.IsSecret(localeTable) then return false end
  if type(preset) ~= "table" or DataUtils.IsSecret(preset) or type(preset.value) ~= "table" or DataUtils.IsSecret(preset.value) then return false end
  local assignments = preset.value.enemyAssignments
  if type(assignments) ~= "table" or DataUtils.IsSecret(assignments) then return true end
  for enemyKey, cloneAssignments in pairs(assignments) do
    local enemyIndex = DataUtils.PositiveInteger(enemyKey)
    if enemyIndex and type(cloneAssignments) == "table" and not DataUtils.IsSecret(cloneAssignments) then
      local marked = false
      for _, marker in pairs(cloneAssignments) do if DataUtils.PositiveInteger(marker, 8) then marked = true break end end
      if marked then
        local enemy = type(enemyData) == "table" and (enemyData[enemyIndex] or enemyData[tostring(enemyIndex)]) or nil
        local rawName = type(enemy) == "table" and not DataUtils.IsSecret(enemy) and type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
        if not rawName or rawName == "" then return false end
        local localized = rawget(localeTable, rawName)
        if DataUtils.IsSecret(localized) or type(localized) ~= "string" or DataUtils.Trim(localized) == "" then return false end
      end
    end
  end
  return true
end

local function readPublicSnapshot(api)
  if type(api) ~= "table" or type(api.GetCurrentRouteSnapshot) ~= "function" then return nil, "unavailable" end
  local raw, errorMessage = safeCall(api.GetCurrentRouteSnapshot, api)
  if not raw then return nil, errorMessage or "public-snapshot-empty" end
  local locale = getClientLocale()
  local rawLocaleStatus = type(raw) == "table" and DataUtils.SafeString(raw.targetNameLocaleStatus, 40, true) or nil
  return Addon.RouteSnapshot.NormalizePublic(raw, {
    mdtVersion = state.version,
    clientLocale = locale,
    targetNameLocaleStatus = rawLocaleStatus or localeStatus(sourceNamesMatchClientLocale(locale)),
  })
end

local function readLegacySnapshot(legacy)
  if type(legacy) ~= "table" or type(legacy.GetCurrentPreset) ~= "function" or type(legacy.GetDB) ~= "function" then
    return nil, "legacy-api-unavailable"
  end
  local db, dbError = safeCall(legacy.GetDB, legacy)
  if not db then return nil, dbError or "legacy-db-unavailable" end
  local preset, presetError = safeCall(legacy.GetCurrentPreset, legacy)
  if not preset then return nil, presetError or "legacy-preset-unavailable" end
  local dungeonIndex = DataUtils.PositiveInteger(db.currentDungeonIdx)
  local presetIndex = type(db.currentPreset) == "table" and DataUtils.PositiveInteger(db.currentPreset[dungeonIndex]) or nil
  local enemyData = type(legacy.dungeonEnemies) == "table" and not DataUtils.IsSecret(legacy.dungeonEnemies) and legacy.dungeonEnemies[dungeonIndex] or nil
  local dungeonName = type(legacy.dungeonList) == "table" and not DataUtils.IsSecret(legacy.dungeonList) and legacy.dungeonList[dungeonIndex] or nil
  local mapInfo = type(legacy.mapInfo) == "table" and not DataUtils.IsSecret(legacy.mapInfo) and legacy.mapInfo[dungeonIndex] or nil
  local challengeMapID = type(mapInfo) == "table" and DataUtils.PositiveInteger(mapInfo.mapID) or resolveChallengeMapID(dungeonName)
  local locale = getClientLocale()
  local localeTable = type(legacy.L) == "table" and not DataUtils.IsSecret(legacy.L) and legacy.L or nil
  local namesVerified = markedLegacyNamesVerified(preset, enemyData, locale, localeTable)
  local resolver
  if localeTable then
    resolver = function(rawName)
      if sourceNamesMatchClientLocale(locale) then return rawName end
      local localized = rawget(localeTable, rawName)
      return type(localized) == "string" and localized ~= "" and not DataUtils.IsSecret(localized) and localized or rawName
    end
  end
  return Addon.RouteSnapshot.NormalizePreset(preset, {
    sourceMode = "legacy-internal",
    compatibility = enemyData and "full" or "limited",
    mdtVersion = state.version,
    dungeonIndex = dungeonIndex,
    dungeonName = dungeonName,
    challengeMapID = challengeMapID,
    presetIndex = presetIndex,
    enemyData = enemyData,
    enemyDataScope = enemyData and "dungeon" or nil,
    enemyNameResolver = resolver,
    clientLocale = locale,
    targetNameLocaleStatus = namesVerified and (sourceNamesMatchClientLocale(locale) and "verified-client-locale" or "verified-mdt-locale") or "unverified-source-locale",
  })
end

local function bindingDatabase(api, legacy, allowUILoad)
  local db
  if type(api) == "table" and type(api.GetDB) == "function" then db = safeCall(api.GetDB, api) end
  if type(db) ~= "table" and type(legacy) == "table" and type(legacy.GetDB) == "function" then db = safeCall(legacy.GetDB, legacy) end
  if type(db) == "table" and type(db.presets) == "table" then return db end
  if allowUILoad == true and not (type(InCombatLockdown) == "function" and InCombatLockdown()) and not state.uiLoaded then
    if loadMDTUIForRouteData() then
      installEnemyMetadataHook()
      if type(api) == "table" and type(api.GetDB) == "function" then db = safeCall(api.GetDB, api) end
      if type(db) ~= "table" and type(legacy) == "table" and type(legacy.GetDB) == "function" then db = safeCall(legacy.GetDB, legacy) end
    end
  end
  return type(db) == "table" and db or nil
end

local function readDBOnlySnapshot(api, allowUILoad)
  local db = bindingDatabase(api, nil, allowUILoad)
  if not db then return nil, "db-unavailable" end
  local preset, presetError, dungeonIndex, presetIndex = currentPresetFromDB(db)
  if not preset then return nil, presetError end

  local liveEnemyData = dungeonIndex and capturedEnemyData[dungeonIndex] or nil
  local hasCaptured = capturedActiveDungeonIndex == dungeonIndex and type(liveEnemyData) == "table" and next(liveEnemyData) ~= nil
  local cachedEnemyData, cachedNamesVerified, cachedDungeonName, cachedChallengeMapID
  if not hasCaptured then cachedEnemyData, cachedNamesVerified, cachedDungeonName, cachedChallengeMapID = matchingCachedEnemyData(dungeonIndex) end
  local hasCached = type(cachedEnemyData) == "table" and next(cachedEnemyData) ~= nil

  local dungeonName = DataUtils.SafeString(cachedDungeonName, 1024, true)
  local challengeMapID = DataUtils.PositiveInteger(cachedChallengeMapID)
  if not dungeonName and state.uiLoaded and type(api.GetDungeonName) == "function" then dungeonName = safeCall(api.GetDungeonName, api, dungeonIndex) end
  if not challengeMapID and dungeonName then challengeMapID = resolveChallengeMapID(dungeonName) end

  local enemyData = hasCaptured and liveEnemyData or (hasCached and cachedEnemyData or nil)
  local namesVerified = hasCaptured and capturedTargetNamesVerified or (hasCached and cachedNamesVerified or false)
  if hasCached and (dungeonName or challengeMapID) then persistCachedDungeonIdentity(dungeonIndex, dungeonName, challengeMapID) end

  return Addon.RouteSnapshot.NormalizePreset(preset, {
    sourceMode = "db-only",
    compatibility = hasCaptured and "route-data+captured-enemy" or (hasCached and "route-data+cached-enemy" or "route-data"),
    mdtVersion = state.version,
    dungeonIndex = dungeonIndex,
    dungeonName = dungeonName,
    challengeMapID = challengeMapID,
    presetIndex = presetIndex,
    enemyData = enemyData,
    enemyDataScope = hasCaptured and "captured-enemy-types" or (hasCached and "cached-enemy-types" or nil),
    clientLocale = getClientLocale(),
    targetNameLocaleStatus = enemyData and localeStatus(namesVerified) or nil,
    expectCloneMetadata = hasCaptured,
  })
end

local function currentBindingDungeonName(binding)
  if type(binding) ~= "table" or DataUtils.IsSecret(binding) then return nil end
  local dungeonIndex = DataUtils.PositiveInteger(binding.dungeonIndex, 1000)
  if not dungeonIndex then return nil end
  local legacy = type(_G.MDT) == "table" and _G.MDT or nil
  if legacy and type(legacy.dungeonList) == "table" and not DataUtils.IsSecret(legacy.dungeonList) then
    local name = DataUtils.SafeString(legacy.dungeonList[dungeonIndex], 1024, true)
    if name then return name end
  end
  local api = type(_G.MythicDungeonToolsAPI) == "table" and _G.MythicDungeonToolsAPI or nil
  if api and type(api.GetDungeonName) == "function" then
    local name = DataUtils.SafeString(safeCall(api.GetDungeonName, api, dungeonIndex), 1024, true)
    if name then return name end
  end
  return DataUtils.SafeString(binding.dungeonName, 1024, true)
end

local function bindingForActiveChallengeMap(challengeMapID)
  challengeMapID = DataUtils.PositiveInteger(challengeMapID) or activeChallengeMapID()
  if not Addon.Database or not challengeMapID then return nil end
  if type(Addon.Database.FindRouteBindingByChallengeMapID) == "function" then
    local binding, bindingError = Addon.Database.FindRouteBindingByChallengeMapID(challengeMapID)
    if binding then return binding, "active-challenge-map" end
    if bindingError and bindingError ~= "route-binding-map-not-found" then return nil, bindingError end
  end
  local wantedName = normalizeDungeonName(challengeMapName(challengeMapID))
  if not wantedName or type(Addon.Database.GetRouteBindings) ~= "function" then return nil, "active-challenge-map-unbound" end
  local match
  for _, binding in pairs(Addon.Database.GetRouteBindings() or {}) do
    if type(binding) == "table" and DataUtils.PositiveInteger(binding.challengeMapID) == nil
      and normalizeDungeonName(currentBindingDungeonName(binding)) == wantedName then
      if match then return nil, "route-binding-name-ambiguous" end
      match = binding
    end
  end
  if not match then return nil, "active-challenge-map-unbound" end
  match.challengeMapID = challengeMapID -- in-memory session promotion only
  return match, "active-challenge-name"
end

local function selectSavedBinding(api, legacy, allowUILoad)
  if not Addon.Database then return nil end
  local mapID = activeChallengeMapID()
  if mapID then
    local binding, bindingError = bindingForActiveChallengeMap(mapID)
    if binding then return binding, "active-challenge-map" end
    return nil, bindingError or "active-challenge-map-unbound"
  end
  local db = bindingDatabase(api, legacy, allowUILoad)
  local dungeonIndex = db and DataUtils.PositiveInteger(db.currentDungeonIdx, 1000) or nil
  if dungeonIndex and type(Addon.Database.GetRouteBinding) == "function" then
    local binding = Addon.Database.GetRouteBinding(dungeonIndex)
    if binding then return binding, "mdt-current-dungeon" end
  end
  return nil
end

local function sortedIdentityKeys(source, maximum)
  if type(source) ~= "table" or DataUtils.IsSecret(source) then return nil, "identity-table-unavailable" end
  local result, seen = {}, {}
  local scanned = 0
  local scanMaximum = math.max(maximum * MAX_ASSIGNMENT_SCAN_MULTIPLIER, maximum + 32)
  for rawKey in pairs(source) do
    scanned = scanned + 1
    if scanned > scanMaximum then return nil, "identity-table-scan-limit-exceeded" end
    local index = DataUtils.PositiveInteger(rawKey)
    if index and not seen[index] then
      seen[index] = true
      result[#result + 1] = index
      if #result > maximum then return nil, "identity-entry-limit-exceeded" end
    end
  end
  table.sort(result)
  return result
end

-- RouteSnapshot's stable identity intentionally depends only on dungeon index and
-- pull/enemy/clone membership. Reproduce that tiny canonical form here so the
-- 250 ms safety watcher does not allocate a complete normalized snapshot four
-- times per second. For valid MDT presets this must remain byte-for-byte identity
-- compatible with RouteSnapshot.NormalizePreset's route-v3 fingerprint.
local function routeKeyForPreset(preset, dungeonIndex, presetIndex)
  if type(preset) ~= "table" or DataUtils.IsSecret(preset)
    or type(preset.value) ~= "table" or DataUtils.IsSecret(preset.value)
    or type(preset.value.pulls) ~= "table" or DataUtils.IsSecret(preset.value.pulls) then
    return nil, nil, "route-identity-preset-invalid"
  end
  dungeonIndex = DataUtils.PositiveInteger(dungeonIndex)
  if not dungeonIndex then return nil, nil, "route-identity-dungeon-invalid" end

  local pullKeys, pullError = sortedIdentityKeys(preset.value.pulls, 500)
  if not pullKeys then return nil, nil, pullError end
  local parts = { "schema=3", "d="..tostring(dungeonIndex) }
  local totalEnemies, totalClones, pullCount = 0, 0, 0
  for _, pullIndex in ipairs(pullKeys) do
    local rawPull = preset.value.pulls[pullIndex] or preset.value.pulls[tostring(pullIndex)]
    if type(rawPull) == "table" and not DataUtils.IsSecret(rawPull) then
      pullCount = pullCount + 1
      parts[#parts + 1] = "p="..tostring(pullIndex)
      local enemyKeys, enemyError = sortedIdentityKeys(rawPull, 500)
      if not enemyKeys then return nil, nil, enemyError end
      for _, enemyIndex in ipairs(enemyKeys) do
        totalEnemies = totalEnemies + 1
        if totalEnemies > 20000 then return nil, nil, "route-identity-enemy-limit-exceeded" end
        parts[#parts + 1] = "e="..tostring(enemyIndex)
        local rawClones = rawPull[enemyIndex] or rawPull[tostring(enemyIndex)]
        if type(rawClones) ~= "table" or DataUtils.IsSecret(rawClones) then
          return nil, nil, "route-identity-clones-unavailable"
        end
        local clones, seenClones, cloneScanned = {}, {}, 0
        for _, rawCloneIndex in pairs(rawClones) do
          cloneScanned = cloneScanned + 1
          if cloneScanned > MAX_ASSIGNMENT_CLONES_PER_ENEMY * MAX_ASSIGNMENT_SCAN_MULTIPLIER then
            return nil, nil, "route-identity-clone-scan-limit-exceeded"
          end
          local cloneIndex = DataUtils.PositiveInteger(rawCloneIndex)
          if cloneIndex and not seenClones[cloneIndex] then
            seenClones[cloneIndex] = true
            clones[#clones + 1] = cloneIndex
            totalClones = totalClones + 1
            if #clones > 1000 or totalClones > 20000 then
              return nil, nil, "route-identity-clone-limit-exceeded"
            end
          elseif rawCloneIndex ~= nil and not cloneIndex then
            return nil, nil, "route-identity-clone-invalid"
          end
        end
        table.sort(clones)
        for _, cloneIndex in ipairs(clones) do parts[#parts + 1] = "c="..tostring(cloneIndex) end
      end
    end
  end

  local fingerprint = "route-v3-"..DataUtils.StableHash(table.concat(parts, "|"))
  local presetUID = DataUtils.SafeString(preset.uid, 1024, true)
  local presetName = DataUtils.SafeString(preset.text or preset.name, 1024, true)
  local identity = {
    routeKey = presetUID and presetUID ~= "" and ("uid:"..presetUID) or ("fp:"..fingerprint),
    fingerprint = fingerprint,
    presetUID = presetUID,
    presetName = presetName,
    presetIndex = DataUtils.PositiveInteger(presetIndex),
    currentPull = DataUtils.PositiveInteger(preset.value.currentPull),
    pullCount = pullCount,
  }
  return identity.routeKey, identity
end

local function resolveBoundPreset(db, binding)
  if type(db) ~= "table" or DataUtils.IsSecret(db) or type(binding) ~= "table" then return nil, "bound-route-db-unavailable" end
  local dungeonIndex = DataUtils.PositiveInteger(binding.dungeonIndex)
  local presets = type(db.presets) == "table" and not DataUtils.IsSecret(db.presets) and db.presets[dungeonIndex] or nil
  if type(presets) ~= "table" or DataUtils.IsSecret(presets) then return nil, "bound-route-dungeon-unavailable" end

  local validate = DataUtils.ValidatedString or DataUtils.SafeString
  local wantedUID = validate(binding.presetUID, 120, true)
  if wantedUID and wantedUID ~= "" then
    for rawIndex, preset in pairs(presets) do
      local presetIndex = DataUtils.PositiveInteger(rawIndex)
      if presetIndex and type(preset) == "table" and not DataUtils.IsSecret(preset)
        and type(preset.value) == "table" and not DataUtils.IsSecret(preset.value)
        and validate(preset.uid, 120, true) == wantedUID then
        return preset, presetIndex, dungeonIndex
      end
    end
    return nil, "bound-route-uid-not-found"
  end

  -- UID-less bindings are strict by membership fingerprint. A unique same-name
  -- route is not sufficient proof that it is the originally bound route.
  local wantedKey = validate(binding.routeKey, 120, true)
  local wantedName = DataUtils.SafeString(binding.presetName, 240, true)
  local exact = {}
  for rawIndex, preset in pairs(presets) do
    local presetIndex = DataUtils.PositiveInteger(rawIndex)
    if presetIndex and type(preset) == "table" and not DataUtils.IsSecret(preset)
      and type(preset.value) == "table" and not DataUtils.IsSecret(preset.value) then
      local key, identity = routeKeyForPreset(preset, dungeonIndex, presetIndex)
      if key == wantedKey then exact[#exact + 1] = { preset = preset, index = presetIndex, name = identity and identity.presetName } end
    end
  end
  if #exact == 1 then return exact[1].preset, exact[1].index, dungeonIndex end
  if #exact > 1 then
    local named = {}
    if wantedName then for _, item in ipairs(exact) do if item.name == wantedName then named[#named + 1] = item end end end
    if #named == 1 then return named[1].preset, named[1].index, dungeonIndex end
    return nil, "bound-route-fingerprint-ambiguous"
  end
  return nil, "bound-route-fingerprint-not-found"
end

local function readBoundSnapshot(api, legacy, binding, allowUILoad)
  local db = bindingDatabase(api, legacy, allowUILoad)
  if not db then return nil, "bound-route-db-unavailable" end
  local preset, presetIndex, dungeonIndex = resolveBoundPreset(db, binding)
  if not preset then return nil, presetIndex end
  local locale = getClientLocale()
  local enemyData, namesVerified, compatibility, enemyDataScope, resolver
  local dungeonName = DataUtils.SafeString(currentBindingDungeonName(binding), 1024, true) or DataUtils.SafeString(binding.dungeonName, 1024, true)
  local challengeMapID = DataUtils.PositiveInteger(binding.challengeMapID)

  if type(legacy) == "table" then
    enemyData = type(legacy.dungeonEnemies) == "table" and not DataUtils.IsSecret(legacy.dungeonEnemies) and legacy.dungeonEnemies[dungeonIndex] or nil
    dungeonName = dungeonName or (type(legacy.dungeonList) == "table" and legacy.dungeonList[dungeonIndex] or nil)
    local mapInfo = type(legacy.mapInfo) == "table" and legacy.mapInfo[dungeonIndex] or nil
    challengeMapID = challengeMapID or (type(mapInfo) == "table" and DataUtils.PositiveInteger(mapInfo.mapID) or nil)
    local localeTable = type(legacy.L) == "table" and not DataUtils.IsSecret(legacy.L) and legacy.L or nil
    namesVerified = markedLegacyNamesVerified(preset, enemyData, locale, localeTable)
    if localeTable then
      resolver = function(rawName)
        if sourceNamesMatchClientLocale(locale) then return rawName end
        local localized = rawget(localeTable, rawName)
        return type(localized) == "string" and localized ~= "" and not DataUtils.IsSecret(localized) and localized or rawName
      end
    end
    compatibility = enemyData and "bound-route+legacy-enemy" or "bound-route-limited"
    enemyDataScope = enemyData and "dungeon" or nil
  else
    local liveEnemyData = dungeonIndex and capturedEnemyData[dungeonIndex] or nil
    local hasCaptured = capturedActiveDungeonIndex == dungeonIndex and type(liveEnemyData) == "table" and next(liveEnemyData) ~= nil
    local cachedEnemyData, cachedNamesVerified, cachedDungeonName, cachedChallengeMapID
    if not hasCaptured then cachedEnemyData, cachedNamesVerified, cachedDungeonName, cachedChallengeMapID = matchingCachedEnemyData(dungeonIndex) end
    local hasCached = type(cachedEnemyData) == "table" and next(cachedEnemyData) ~= nil
    enemyData = hasCaptured and liveEnemyData or (hasCached and cachedEnemyData or nil)
    namesVerified = hasCaptured and capturedTargetNamesVerified or (hasCached and cachedNamesVerified or false)
    dungeonName = dungeonName or DataUtils.SafeString(cachedDungeonName, 1024, true)
    challengeMapID = challengeMapID or DataUtils.PositiveInteger(cachedChallengeMapID)
    if not dungeonName and type(api) == "table" and type(api.GetDungeonName) == "function" then dungeonName = safeCall(api.GetDungeonName, api, dungeonIndex) end
    compatibility = hasCaptured and "bound-route+captured-enemy" or (hasCached and "bound-route+cached-enemy" or "bound-route")
    enemyDataScope = hasCaptured and "captured-enemy-types" or (hasCached and "cached-enemy-types" or nil)
  end

  if not challengeMapID and dungeonName then challengeMapID = resolveChallengeMapID(dungeonName) end
  local snapshot, snapshotError = Addon.RouteSnapshot.NormalizePreset(preset, {
    sourceMode = "bound-route",
    compatibility = compatibility,
    mdtVersion = state.version,
    dungeonIndex = dungeonIndex,
    dungeonName = dungeonName,
    challengeMapID = challengeMapID,
    presetIndex = presetIndex,
    enemyData = enemyData,
    enemyDataScope = enemyDataScope,
    enemyNameResolver = resolver,
    clientLocale = locale,
    targetNameLocaleStatus = enemyData and (type(legacy) == "table"
      and (namesVerified and (sourceNamesMatchClientLocale(locale) and "verified-client-locale" or "verified-mdt-locale") or "unverified-source-locale")
      or localeStatus(namesVerified)) or nil,
    expectCloneMetadata = type(legacy) ~= "table" and capturedActiveDungeonIndex == dungeonIndex,
  })
  if not snapshot then return nil, snapshotError end
  if snapshot.routeKey ~= binding.routeKey then return nil, "bound-route-identity-changed" end
  return snapshot
end

local function appendAssignmentSignature(parts, preset)
  local assignments = type(preset) == "table" and type(preset.value) == "table" and preset.value.enemyAssignments or nil
  if type(assignments) ~= "table" or DataUtils.IsSecret(assignments) then return true end
  local keys, scanned, seenEnemies = {}, 0, {}
  local enemyScanMaximum = MAX_ASSIGNMENT_ENEMIES * MAX_ASSIGNMENT_SCAN_MULTIPLIER
  for enemyKey in pairs(assignments) do
    scanned = scanned + 1
    if scanned > enemyScanMaximum then return nil, "route-signature-assignment-enemy-scan-limit-exceeded" end
    local enemyIndex = DataUtils.PositiveInteger(enemyKey)
    if enemyIndex and not seenEnemies[enemyIndex] then
      if #keys >= MAX_ASSIGNMENT_ENEMIES then return nil, "route-signature-assignment-enemy-limit-exceeded" end
      seenEnemies[enemyIndex] = true
      keys[#keys + 1] = enemyIndex
    end
  end
  table.sort(keys)
  local total = 0
  for _, enemyIndex in ipairs(keys) do
    local cloneAssignments = assignments[enemyIndex] or assignments[tostring(enemyIndex)]
    if type(cloneAssignments) == "table" and not DataUtils.IsSecret(cloneAssignments) then
      local cloneKeys, cloneScanned, seenClones = {}, 0, {}
      local cloneScanMaximum = MAX_ASSIGNMENT_CLONES_PER_ENEMY * MAX_ASSIGNMENT_SCAN_MULTIPLIER
      for cloneKey in pairs(cloneAssignments) do
        cloneScanned = cloneScanned + 1
        if cloneScanned > cloneScanMaximum then return nil, "route-signature-assignment-clone-scan-limit-exceeded" end
        local cloneIndex = DataUtils.PositiveInteger(cloneKey)
        if cloneIndex and not seenClones[cloneIndex] then
          if #cloneKeys >= MAX_ASSIGNMENT_CLONES_PER_ENEMY then return nil, "route-signature-assignment-clone-limit-exceeded" end
          seenClones[cloneIndex] = true
          total = total + 1
          if total > MAX_ASSIGNMENT_TOTAL then return nil, "route-signature-assignment-total-limit-exceeded" end
          cloneKeys[#cloneKeys + 1] = cloneIndex
        end
      end
      table.sort(cloneKeys)
      for _, cloneIndex in ipairs(cloneKeys) do
        local marker = cloneAssignments[cloneIndex] or cloneAssignments[tostring(cloneIndex)] or 0
        parts[#parts + 1] = ("%d:%d:%s"):format(enemyIndex, cloneIndex, tostring(marker))
      end
    end
  end
  return true
end

-- MDT 6.2.1 exposes a stable core DB but no public route-mutation callback. Keep a
-- cheap out-of-combat signature for both explicitly bound routes and legacy
-- current-route mode. Membership fingerprinting is included even for UID routes:
-- a stable UID proves route identity, not that its pulls have not changed.
local function lightweightRouteSignature()
  local api = type(_G.MythicDungeonToolsAPI) == "table" and _G.MythicDungeonToolsAPI or nil
  local legacy = type(_G.MDT) == "table" and _G.MDT or nil
  local db = bindingDatabase(api, legacy, false)
  if not db then return nil, "route-db-unavailable" end

  local binding = Adapter:GetRouteBinding()
  local preset, presetError, presetIndex, dungeonIndex
  local scope
  if binding then
    preset, presetIndex, dungeonIndex = resolveBoundPreset(db, binding)
    if not preset then return nil, presetIndex or "bound-route-unavailable" end
    scope = "bound"
  else
    preset, presetError, dungeonIndex, presetIndex = currentPresetFromDB(db)
    if not preset then return nil, presetError or "active-route-unavailable" end
    scope = "current"
  end

  local _, identity = routeKeyForPreset(preset, dungeonIndex, presetIndex)
  if not identity then return nil, "route-identity-unavailable" end
  local parts = {
    scope,
    tostring(dungeonIndex or 0),
    tostring(presetIndex or 0),
    tostring(identity.routeKey or ""),
    tostring(identity.fingerprint or ""),
    tostring(identity.presetUID or ""),
    tostring(identity.presetName or ""),
  }
  if scope == "current" then parts[#parts + 1] = tostring(identity.currentPull or 0) end
  local assignmentsOK, assignmentError = appendAssignmentSignature(parts, preset)
  if not assignmentsOK then return nil, assignmentError end
  return DataUtils.StableHash(table.concat(parts, "|"))
end

local function rebuildAfterRouteWatch(reason)
  local snapshot = Adapter:Refresh(reason)
  if Addon.RuntimeController and type(Addon.RuntimeController.Refresh) == "function" then
    Addon.RuntimeController:Refresh(reason, snapshot ~= nil)
  end
end

local function scheduleRouteMutationRefresh(reason)
  if routeMutationRefreshScheduled then return end
  routeMutationRefreshScheduled = true
  local function refresh()
    routeMutationRefreshScheduled = false
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    local signature = lightweightRouteSignature()
    rebuildAfterRouteWatch(reason or "mdt-route-interaction")
    routeWatchSignature = signature or routeWatchSignature
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(0, refresh) else refresh() end
end

local function onPotentialRouteMutation(_, reason)
  -- During combat the execution contract is intentionally frozen: WoW cannot
  -- rewrite protected macro bodies safely. Changes are observed and applied
  -- after combat. Out of combat, park synchronously before the deferred rebuild;
  -- this closes the pre-combat polling race.
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    routeMutationObservedInCombat = true
    return false, "combat-route-frozen"
  end
  invalidateExecution(reason or "mdt-route-interaction")
  scheduleRouteMutationRefresh(reason or "mdt-route-interaction")
  return true
end

local function installRouteMutationHooks()
  if routeMutationHooksInstalled then return true end
  if type(hooksecurefunc) ~= "function" then return nil, "mdt-route-mutation-hook-unavailable" end

  local installed = 0
  local function install(target, methodName, reasonPrefix)
    if type(target) ~= "table" or type(target[methodName]) ~= "function" then return end
    local ok = pcall(hooksecurefunc, target, methodName, function()
      onPotentialRouteMutation(nil, tostring(reasonPrefix)..tostring(methodName))
    end)
    if ok then installed = installed + 1 end
  end

  -- MDT 6.2.x mutates enemy membership through the public MDT method during
  -- both click and drag-preview flows. Hook the mutator itself so drag scripts
  -- do not depend on mixin method names that are installed via SetScript.
  local mixin = _G.MDTDungeonEnemyMixin
  install(mixin, "OnClick", "mdt-route-interaction:")
  install(mixin, "SetUp", "mdt-enemy-setup:")

  local mdt = type(_G.MDT) == "table" and _G.MDT or nil
  install(mdt, "DungeonEnemies_AddOrRemoveBlipToCurrentPull", "mdt-route-mutator:")
  install(mdt, "PresetsAddPull", "mdt-route-mutator:")

  if installed == 0 then return nil, "mdt-route-mutation-methods-unavailable" end
  routeMutationHooksInstalled = true
  return true
end

local function runRouteWatchTick()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "in-combat" end
  local signature, signatureError = lightweightRouteSignature()
  if not signature then
    -- Losing route data after a previously valid signature is itself a state
    -- transition. Park first; never silently forget the baseline while an old
    -- macro body remains executable.
    if routeWatchSignature then
      invalidateExecution("mdt-route-data-unavailable:"..tostring(signatureError or "unknown"))
      rebuildAfterRouteWatch("mdt-route-data-unavailable")
    end
    routeWatchSignature = nil
    return false, signatureError or "route-data-unavailable"
  end
  if routeWatchSignature and routeWatchSignature ~= signature then
    invalidateExecution("mdt-route-data-changed")
    rebuildAfterRouteWatch("mdt-route-data-changed")
  elseif routeMutationObservedInCombat then
    -- The route may have returned to the same signature, but a combat-time edit
    -- was observed. Revalidate once after combat before reusing execution state.
    invalidateExecution("mdt-route-combat-edit-revalidate")
    rebuildAfterRouteWatch("mdt-route-combat-edit-revalidate")
  end
  routeMutationObservedInCombat = false
  routeWatchSignature = signature
  return true, signature
end

local function ensureRouteWatch()
  if routeWatchTicker or type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end
  routeWatchTicker = C_Timer.NewTicker(0.25, runRouteWatchTick)
end

function Adapter:ValidateExecutionFreshness(reason)
  -- Last synchronous fail-closed check at combat entry. Official MDT mutation
  -- paths are hooked out of combat; this additionally catches direct/programmatic
  -- DB edits that occurred between route-watch ticks. Reading the route is safe
  -- in combat even though protected macro writes are not.
  local signature, signatureError = lightweightRouteSignature()
  if not signature then
    invalidateExecution((reason or "execution-freshness")..":route-data-unavailable")
    routeMutationObservedInCombat = true
    return false, signatureError or "route-data-unavailable"
  end
  if not routeWatchSignature then
    invalidateExecution((reason or "execution-freshness")..":baseline-unavailable")
    routeMutationObservedInCombat = true
    return false, "route-watch-baseline-unavailable"
  end
  if routeWatchSignature ~= signature then
    invalidateExecution((reason or "execution-freshness")..":route-changed")
    routeMutationObservedInCombat = true
    return false, "route-signature-changed"
  end
  return true, signature
end

local function registerUIInitializer(api)
  if initializerRegistered or type(api) ~= "table" or type(api.RegisterUIInitializer) ~= "function" then return end
  initializerRegistered = true
  local ok = pcall(api.RegisterUIInitializer, api, function()
    installEnemyMetadataHook()
    installRouteMutationHooks()
    ensureRouteWatch()
    invalidateExecution("mdt-ui-initialized")
    Adapter:Refresh("mdt-ui-initialized")
    if Addon.RuntimeController and type(Addon.RuntimeController.Refresh) == "function" then
      Addon.RuntimeController:Refresh("mdt-ui-initialized", true)
    end
  end)
  if not ok then initializerRegistered = false end
end

function Adapter:Initialize()
  installRouteMutationHooks()
  ensureRouteWatch()
  return self:Refresh("initialize")
end

function Adapter:Refresh(reason, options)
  resetState(reason or "refresh")
  options = type(options) == "table" and options or {}
  local api = type(_G.MythicDungeonToolsAPI) == "table" and _G.MythicDungeonToolsAPI or nil
  local legacy = type(_G.MDT) == "table" and _G.MDT or nil
  local versionRaw = getMetadata("Version")
  local parsedVersion = parseVersion(versionRaw)
  local coreLoaded = isLoaded(MDT_ADDON)

  state.installed = api ~= nil or legacy ~= nil or versionRaw ~= nil or coreLoaded
  state.loaded = api ~= nil or legacy ~= nil or coreLoaded
  state.uiLoaded = isLoaded(MDT_UI_ADDON)
  state.version = versionRaw
  state.versionStatus = classifyVersion(parsedVersion)
  if state.uiLoaded then installEnemyMetadataHook() end
  if api then registerUIInitializer(api) end
  ensureRouteWatch()

  if not state.installed then state.lastError = "mdt-not-installed" return nil, state.lastError end

  local snapshot, snapshotError
  local binding, bindingSelection
  if not options.ignoreBinding then
    binding, bindingSelection = selectSavedBinding(api, legacy, options.allowUILoad == true)
    if not binding and bindingSelection and bindingSelection ~= "active-challenge-map-unbound" then
      state.mode = "bound-route-unavailable"
      state.lastError = bindingSelection
      return nil, state.lastError
    end
  end
  if binding then
    state.activeBinding = DataUtils.DeepCopy(binding)
    snapshot, snapshotError = readBoundSnapshot(api, legacy, binding, options.allowUILoad == true)
    if not snapshot then state.mode = "bound-route-unavailable" state.lastError = snapshotError or "bound-route-unavailable" return nil, state.lastError end
    state.mode = "bound-route"
    state.compatibility = snapshot.compatibility or "bound-route"
  end
  if not snapshot and api and type(api.GetCurrentRouteSnapshot) == "function" then
    snapshot, snapshotError = readPublicSnapshot(api)
    if snapshot then state.mode = "public-snapshot" state.compatibility = "full" else addStateWarning("public-snapshot-failed", snapshotError) end
  end
  if not snapshot and legacy then
    snapshot, snapshotError = readLegacySnapshot(legacy)
    if snapshot then state.mode = "legacy-internal" state.compatibility = snapshot.compatibility or "limited" else addStateWarning("legacy-snapshot-failed", snapshotError) end
  end
  if not snapshot and api then
    snapshot, snapshotError = readDBOnlySnapshot(api, options.allowUILoad == true)
    if snapshot then
      state.mode = "db-only"
      state.compatibility = snapshot.compatibility or "route-data"
      if state.compatibility == "route-data" then addStateWarning("enemy-metadata-unavailable", "MDT route data is available, but enemy identity metadata is not available yet.") end
    else
      addStateWarning("db-snapshot-failed", snapshotError)
    end
  end

  if snapshot then
    state.snapshot = snapshot
    if snapshot.enemyNameScope == "captured-enemy-types" or snapshot.enemyNameScope == "cached-enemy-types" then
      addStateWarning("dungeon-name-coverage-partial", "Captured metadata is complete only for known enemy types; route-wide ambiguity remains the guaranteed baseline.")
    end
    if state.versionStatus == "too-old" then state.snapshot = nil state.compatibility = "unavailable" state.lastError = "mdt-version-too-old" return nil, state.lastError end
    if state.versionStatus == "compatible-range" then addStateWarning("unverified-mdt-version", state.version) end
    if state.versionStatus == "untested-newer" then addStateWarning("untested-mdt-version", state.version) end
    routeWatchSignature = lightweightRouteSignature() or routeWatchSignature
    return self:GetSnapshot()
  end

  state.mode = state.loaded and "waiting-route-data" or "installed-not-loaded"
  state.compatibility = "unavailable"
  state.lastError = snapshotError or "route-data-unavailable"
  return nil, state.lastError
end

function Adapter:GetRouteBinding(dungeonIndex)
  dungeonIndex = DataUtils.PositiveInteger(dungeonIndex, 1000)
  if dungeonIndex and Addon.Database and type(Addon.Database.GetRouteBinding) == "function" then return Addon.Database.GetRouteBinding(dungeonIndex) end
  local mapID = activeChallengeMapID()
  if mapID then return bindingForActiveChallengeMap(mapID) end
  if state.activeBinding then return DataUtils.DeepCopy(state.activeBinding) end
  local snapshotDungeon = state.snapshot and DataUtils.PositiveInteger(state.snapshot.dungeonIndex, 1000) or nil
  return snapshotDungeon and Addon.Database and Addon.Database.GetRouteBinding and Addon.Database.GetRouteBinding(snapshotDungeon) or nil
end

function Adapter:GetRouteBindings()
  return Addon.Database and type(Addon.Database.GetRouteBindings) == "function" and Addon.Database.GetRouteBindings() or {}
end

function Adapter:BindCurrentRoute()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "in-combat" end
  invalidateExecution("bind-current-route")
  local snapshot, snapshotError = self:Refresh("bind-current-route", { ignoreBinding = true, allowUILoad = true })
  if not snapshot then return nil, snapshotError or "route-unavailable" end
  if not snapshot.routeKey or not snapshot.dungeonIndex then return nil, "route-identity-unavailable" end
  local liveMapID = activeChallengeMapID()
  local routeMapID = DataUtils.PositiveInteger(snapshot.challengeMapID)
  if liveMapID then
    if not routeMapID then
      if normalizeDungeonName(challengeMapName(liveMapID)) ~= normalizeDungeonName(snapshot.dungeonName) then return nil, "bind-route-active-dungeon-unverified" end
      routeMapID = liveMapID
    end
    if routeMapID ~= liveMapID then return nil, "bind-route-active-dungeon-mismatch" end
  end
  local binding = {
    routeKey = snapshot.routeKey,
    presetUID = snapshot.presetUID,
    presetName = snapshot.presetName,
    presetIndex = snapshot.presetIndex,
    dungeonIndex = snapshot.dungeonIndex,
    dungeonName = snapshot.dungeonName,
    challengeMapID = routeMapID,
    boundFingerprint = snapshot.fingerprint,
    mdtVersion = snapshot.mdtVersion or state.version,
  }
  local previous = Addon.Database.GetRouteBinding and Addon.Database.GetRouteBinding(binding.dungeonIndex) or nil
  local saved, saveError = Addon.Database.SetRouteBinding(binding)
  if not saved then return nil, saveError or "route-binding-save-failed" end
  local rebound, reboundError = self:Refresh("route-bound", { allowUILoad = true })
  if not rebound then
    if previous then Addon.Database.SetRouteBinding(previous) else Addon.Database.ClearRouteBinding(binding.dungeonIndex) end
    self:Refresh("route-bind-rollback", { allowUILoad = true })
    return nil, reboundError or "bound-route-refresh-failed"
  end
  return self:GetRouteBinding(binding.dungeonIndex)
end

function Adapter:ClearRouteBinding(dungeonIndex)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "in-combat" end
  invalidateExecution("route-unbind")
  dungeonIndex = DataUtils.PositiveInteger(dungeonIndex, 1000)
  if not dungeonIndex then
    local binding = activeChallengeMapID() and bindingForActiveChallengeMap(activeChallengeMapID()) or nil
    dungeonIndex = binding and DataUtils.PositiveInteger(binding.dungeonIndex, 1000) or nil
  end
  dungeonIndex = dungeonIndex or (state.activeBinding and DataUtils.PositiveInteger(state.activeBinding.dungeonIndex, 1000))
    or (state.snapshot and DataUtils.PositiveInteger(state.snapshot.dungeonIndex, 1000))
  if not dungeonIndex then return nil, "route-binding-dungeon-required" end
  local cleared, clearError = Addon.Database.ClearRouteBinding(dungeonIndex)
  if not cleared then return nil, clearError or "route-binding-clear-failed" end
  self:Refresh("route-unbound", { allowUILoad = true })
  return true
end

function Adapter:ListRoutes(options)
  options = type(options) == "table" and options or {}
  local api = type(_G.MythicDungeonToolsAPI) == "table" and _G.MythicDungeonToolsAPI or nil
  local legacy = type(_G.MDT) == "table" and _G.MDT or nil
  local db = bindingDatabase(api, legacy, options.allowUILoad == true)
  if not db then return nil, "route-db-unavailable" end
  local dungeonIndex = DataUtils.PositiveInteger(options.dungeonIndex or db.currentDungeonIdx)
  local presets = dungeonIndex and type(db.presets) == "table" and db.presets[dungeonIndex] or nil
  if type(presets) ~= "table" or DataUtils.IsSecret(presets) then return nil, "route-list-unavailable" end
  local binding = Addon.Database and Addon.Database.GetRouteBinding and Addon.Database.GetRouteBinding(dungeonIndex) or nil
  local result = {}
  for rawIndex, preset in pairs(presets) do
    local presetIndex = DataUtils.PositiveInteger(rawIndex)
    if presetIndex and type(preset) == "table" and not DataUtils.IsSecret(preset)
      and type(preset.value) == "table" and type(preset.value.pulls) == "table" then
      local routeKey, identity = routeKeyForPreset(preset, dungeonIndex, presetIndex)
      if routeKey and identity then
        result[#result + 1] = {
          routeKey = routeKey,
          presetUID = identity.presetUID,
          presetName = identity.presetName or ("Route "..tostring(presetIndex)),
          presetIndex = presetIndex,
          dungeonIndex = dungeonIndex,
          pullCount = tonumber(identity.pullCount) or 0,
          current = type(db.currentPreset) == "table" and tonumber(db.currentPreset[dungeonIndex]) == presetIndex or false,
          bound = binding and ((binding.presetUID and identity.presetUID == binding.presetUID) or (not binding.presetUID and binding.routeKey == routeKey)) or false,
        }
      end
    end
  end
  table.sort(result, function(left, right) return left.presetIndex < right.presetIndex end)
  return result
end

function Adapter:SyncActiveRoute()
  local snapshot, refreshError = self:Refresh("backend-sync")
  if not snapshot then return nil, refreshError end
  return { status = snapshot.nativeAssignmentsAvailable == true and "ready" or "ready-limited", routeKey = snapshot.routeKey, action = "snapshot-refreshed" }
end

function Adapter:BuildMarkerPlan(options)
  local databaseState = Addon.Database and type(Addon.Database.GetState) == "function" and Addon.Database.GetState() or nil
  if databaseState and databaseState.blocked == true then
    return nil, { { severity = "error", code = "database-blocked", path = "database" } }
  end
  local snapshot = self:GetSnapshot()
  if not snapshot then return nil, { { severity = "error", code = state.lastError or "route-unavailable", path = "mdt" } } end
  local global = Addon.Database.GetGlobal and Addon.Database.GetGlobal() or {}
  options = type(options) == "table" and options or {}
  local preserve = options.preserveExistingMarkers
  if preserve == nil then preserve = global.preserveExistingMarkers ~= false end
  local maxBatches = options.maxBatches
  if maxBatches == nil then maxBatches = self:GetRouteBinding() and 3 or 2 end
  return Addon.MarkerPlanner.Build(snapshot, { preserveExistingMarkers = preserve, maxBatches = maxBatches })
end

function Adapter:ValidateActiveRoute()
  local plan, findings = self:BuildMarkerPlan()
  findings = findings or {}
  if Addon.MDTFocusMarkerBridge and type(Addon.MDTFocusMarkerBridge.GetFindings) == "function" then
    for _, item in ipairs(Addon.MDTFocusMarkerBridge:GetFindings(self:GetSnapshot()) or {}) do findings[#findings + 1] = item end
  end
  return plan ~= nil and plan.status ~= "blocked", findings
end

function Adapter:GetSnapshot()
  return Addon.RouteSnapshot.Copy(state.snapshot)
end

function Adapter:GetStatus()
  return {
    status = state.snapshot and (state.snapshot.nativeAssignmentsAvailable == true and "ready" or "ready-limited") or "route-unavailable",
    lastAction = state.lastRefreshReason,
    installed = state.installed,
    loaded = state.loaded,
    uiLoaded = state.uiLoaded,
    version = state.version,
    versionStatus = state.versionStatus,
    mode = state.mode,
    compatibility = state.compatibility,
    lastError = state.lastError,
    warnings = Addon.RouteSnapshot.Copy(state.warnings),
    fingerprint = state.snapshot and state.snapshot.fingerprint or nil,
    routeKey = state.snapshot and state.snapshot.routeKey or nil,
    pullCount = state.snapshot and #state.snapshot.pulls or 0,
    enemyHookInstalled = enemyHookInstalled,
    routeBinding = self:GetRouteBinding(),
    routeBindingCount = (function() local count = 0 for _ in pairs(self:GetRouteBindings()) do count = count + 1 end return count end)(),
    boundRoute = self:GetRouteBinding() ~= nil,
    lastRefreshReason = state.lastRefreshReason,
  }
end

function Adapter:PrintStatus()
  local status = self:GetStatus()
  Addon.Chat(("MDT version: %s"):format(tostring(status.version or "unknown")))
  Addon.Chat(("Mode: %s"):format(tostring(status.mode)))
  Addon.Chat(("Compatibility: %s"):format(tostring(status.compatibility)))
  Addon.Chat(("Core loaded: %s; UI loaded: %s"):format(status.loaded and "yes" or "no", status.uiLoaded and "yes" or "no"))
  if status.lastError then Addon.Chat("Last error: "..tostring(status.lastError)) end
  if status.fingerprint then Addon.Chat("Route fingerprint: "..status.fingerprint) end
  for _, warning in ipairs(status.warnings or {}) do Addon.Chat(("Warning: %s%s"):format(tostring(warning.code), warning.detail and " - "..tostring(warning.detail) or "")) end
end

function Adapter:PrintRouteSummary()
  local snapshot = self:GetSnapshot()
  if not snapshot then Addon.Chat("No normalized MDT route is currently available.") self:PrintStatus() return end
  local enemyCount, cloneCount = 0, 0
  for _, pull in ipairs(snapshot.pulls) do
    enemyCount = enemyCount + #pull.enemies
    for _, enemy in ipairs(pull.enemies) do cloneCount = cloneCount + #enemy.clones end
  end
  Addon.Chat(("Route: %s; dungeon %s; pulls %d; enemy groups %d; clones %d"):format(
    tostring(snapshot.presetName or snapshot.presetUID or "unnamed"), tostring(snapshot.dungeonIndex or "unknown"), #snapshot.pulls, enemyCount, cloneCount
  ))
  Addon.Chat("Fingerprint: "..tostring(snapshot.fingerprint))
  Addon.Chat("Source mode: "..tostring(snapshot.sourceMode).." / "..tostring(snapshot.compatibility))
end

if rawget(_G, "MDTPullMarker_TESTING") == true then
  Adapter._Test = {
    LightweightRouteSignature = lightweightRouteSignature,
    RunRouteWatchTick = runRouteWatchTick,
    RouteKeyForPreset = routeKeyForPreset,
    AppendAssignmentSignature = appendAssignmentSignature,
    InstallRouteMutationHooks = installRouteMutationHooks,
    ScheduleRouteMutationRefresh = scheduleRouteMutationRefresh,
    OnPotentialRouteMutation = onPotentialRouteMutation,
  }
end

Adapter.ParseVersion = parseVersion
Adapter.ClassifyVersion = classifyVersion
