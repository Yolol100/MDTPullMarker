local _, Addon = ...

local Adapter = {}
Addon.MDT = Adapter
-- Backwards-compatible alias: route access and plan building now share one state.
Addon.Backend = Adapter

local DataUtils = Addon.DataUtils

local MDT_ADDON = "MythicDungeonTools"
local MDT_UI_ADDON = "MythicDungeonTools_UI"
local TESTED_MIN = { 6, 1, 17 }
local TESTED_MAX_EXCLUSIVE = { 6, 3, 0 }
local VERIFIED_LOCAL_VERSIONS = {}
local VERIFIED_SOURCE_VERSIONS = {
  ["6.1.20"] = true,
  ["6.2.0-alpha5"] = true,
  ["6.2.1"] = true,
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
local uiInitializerRefreshScheduled = false
local enemyHookInstalled = false
local enemyCaptureRefreshScheduled = false
local enemyCaptureSerial = 0
local capturedEnemyData = {}
local capturedActiveDungeonIndex
local capturedTargetNamesVerified = false
local installEnemyMetadataHook

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
  if type(GetAddOnMetadata) == "function" then
    return safeCall(GetAddOnMetadata, MDT_ADDON, field)
  end
end

local function isLoaded(addon)
  if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
    local first, second = safeCall(C_AddOns.IsAddOnLoaded, addon)
    if second == nil and type(first) == "boolean" then return first end
    if type(second) == "boolean" then return second end
  end
  if type(IsAddOnLoaded) == "function" then
    local loaded = safeCall(IsAddOnLoaded, addon)
    return loaded == true
  end
  return false
end

local function loadMDTUIForRouteData()
  if isLoaded(MDT_UI_ADDON) then
    state.uiLoaded = true
    return true
  end
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
  if VERIFIED_LOCAL_VERSIONS[version.raw] then return "verified-local" end
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

local function normalizeDungeonName(value)
  return DataUtils.NormalizeName(value)
end

local function getClientLocale()
  if type(GetLocale) == "function" then
    local locale = safeCall(GetLocale)
    locale = DataUtils.SafeString(locale, 16, true)
    if locale then return locale end
  end
  return "unknown"
end

local function sourceNamesMatchClientLocale(locale) return locale == "enUS" or locale == "enGB" end
local function localeStatus(verified) return verified and "verified-client-locale" or "unverified-source-locale" end

local function resolveChallengeMapID(dungeonName)
  local wanted = normalizeDungeonName(dungeonName)
  if not wanted or type(C_ChallengeMode) ~= "table"
    or type(C_ChallengeMode.GetMapTable) ~= "function"
    or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then return nil end

  local mapIDs = safeCall(C_ChallengeMode.GetMapTable)
  if type(mapIDs) ~= "table" or (Addon.IsSecret and Addon.IsSecret(mapIDs)) then return nil end
  for _, mapID in ipairs(mapIDs) do
    local numericMapID = DataUtils.PositiveInteger(mapID)
    if numericMapID then
      local name = safeCall(C_ChallengeMode.GetMapUIInfo, numericMapID)
      if normalizeDungeonName(name) == wanted then return numericMapID end
    end
  end
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

local function buildCapturedMetadataCache()
  local dungeonIndex = capturedActiveDungeonIndex
  local dungeon = dungeonIndex and capturedEnemyData[dungeonIndex] or nil
  if type(dungeon) ~= "table" or next(dungeon) == nil then return nil end
  local enemies = {}
  for enemyIndex, enemy in pairs(dungeon) do
    enemyIndex = DataUtils.PositiveInteger(enemyIndex)
    if enemyIndex and type(enemy) == "table" and not DataUtils.IsSecret(enemy) then
      local npcID = DataUtils.PositiveInteger(enemy.id or enemy.npcID)
      local name = type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
      if name and (name == "" or #name > 1024) then name = nil end
      local cloneCount = 0
      if type(enemy.clones) == "table" and not DataUtils.IsSecret(enemy.clones) then
        for cloneIndex in pairs(enemy.clones) do if DataUtils.PositiveInteger(cloneIndex) then cloneCount=cloneCount+1 end if cloneCount>=1000 then break end end
      end
      if npcID and name and cloneCount>0 then enemies[enemyIndex]={id=npcID,name=name,cloneCount=cloneCount} end
    end
  end
  if next(enemies)==nil then return nil end
  local snapshot = state.snapshot
  local cachedDungeonName = snapshot and DataUtils.SafeString(snapshot.dungeonName, 1024, true) or nil
  local cachedChallengeMapID = snapshot and DataUtils.PositiveInteger(snapshot.challengeMapID) or nil
  return {
    dungeonIndex=dungeonIndex,
    dungeonName=cachedDungeonName,
    challengeMapID=cachedChallengeMapID,
    mdtVersion=DataUtils.SafeString(state.version or getMetadata("Version"),40,true),
    locale=getClientLocale(),
    targetNamesVerified=capturedTargetNamesVerified==true,
    enemies=enemies,
  }
end

local function persistCapturedMetadataCache()
  if not (Addon.Database and type(Addon.Database.SaveEnemyMetadataCache)=="function") then return end
  local cache=buildCapturedMetadataCache()
  if not cache or not cache.mdtVersion then return end
  local saved, saveError=Addon.Database.SaveEnemyMetadataCache(cache)
  if not saved and Addon.Log then Addon.Log("WARN","MDT enemy metadata cache was not saved: "..tostring(saveError),false) end
end

local function matchingCachedEnemyData(dungeonIndex)
  if not (Addon.Database and type(Addon.Database.GetEnemyMetadataCache)=="function") then return nil end
  local cache=Addon.Database.GetEnemyMetadataCache()
  if type(cache)~="table" then return nil end
  if DataUtils.PositiveInteger(cache.dungeonIndex)~=dungeonIndex then return nil end
  if tostring(cache.mdtVersion or "")~=tostring(state.version or "") then return nil end
  if tostring(cache.locale or "")~=getClientLocale() then return nil end
  if type(cache.enemies)~="table" or next(cache.enemies)==nil then return nil end
  return cache.enemies, cache.targetNamesVerified==true, cache.dungeonName, cache.challengeMapID
end

local function persistCachedDungeonIdentity(dungeonIndex, dungeonName, challengeMapID)
  if not (Addon.Database and type(Addon.Database.GetEnemyMetadataCache)=="function"
    and type(Addon.Database.SaveEnemyMetadataCache)=="function") then return end
  local cache=Addon.Database.GetEnemyMetadataCache()
  if type(cache)~="table" or DataUtils.PositiveInteger(cache.dungeonIndex)~=dungeonIndex then return end
  if tostring(cache.mdtVersion or "")~=tostring(state.version or "") or tostring(cache.locale or "")~=getClientLocale() then return end
  dungeonName=DataUtils.SafeString(dungeonName,1024,true)
  challengeMapID=DataUtils.PositiveInteger(challengeMapID)
  if cache.dungeonName==dungeonName and DataUtils.PositiveInteger(cache.challengeMapID)==challengeMapID then return end
  if dungeonName then cache.dungeonName=dungeonName end
  if challengeMapID then cache.challengeMapID=challengeMapID end
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
    if Addon.ConfigurationUI and type(Addon.ConfigurationUI.Refresh) == "function"
      and Addon.ConfigurationUI.HasViews and Addon.ConfigurationUI:HasViews() then
      Addon.ConfigurationUI:Refresh()
    end
    if Addon.RuntimeFrame and Addon.RuntimeFrame.IsOpen and Addon.RuntimeFrame:IsOpen()
      and type(Addon.RuntimeFrame.Refresh) == "function" then
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
  -- MDT 6.2 keeps its localization table on the load-on-demand UI's local MDT
  -- object and does not expose that table through the public plugin API. Do not
  -- infer that a source English name is localized merely because a legacy/global
  -- MDT table happens to exist. Non-English 6.2 capture therefore remains
  -- fail-closed until a trustworthy client-locale name is supplied by MDT.
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
    local copied = 0
    for sourceCloneIndex, sourceClone in pairs(sourceClones) do
      sourceCloneIndex = DataUtils.PositiveInteger(sourceCloneIndex)
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

installEnemyMetadataHook = function()
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

local function readPublicSnapshot(api)
  if type(api) ~= "table" or type(api.GetCurrentRouteSnapshot) ~= "function" then return nil, "unavailable" end
  local raw, errorMessage = safeCall(api.GetCurrentRouteSnapshot, api)
  if not raw then return nil, errorMessage or "public-snapshot-empty" end
  local locale=getClientLocale()
  local rawLocaleStatus=type(raw)=="table" and DataUtils.SafeString(raw.targetNameLocaleStatus,40,true) or nil
  return Addon.RouteSnapshot.NormalizePublic(raw,{mdtVersion=state.version,clientLocale=locale,targetNameLocaleStatus=rawLocaleStatus or localeStatus(sourceNamesMatchClientLocale(locale))})
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
      for _, marker in pairs(cloneAssignments) do
        marker = DataUtils.PositiveInteger(marker, 8)
        if marker then marked = true break end
      end
      if marked then
        local enemy = type(enemyData) == "table" and (enemyData[enemyIndex] or enemyData[tostring(enemyIndex)]) or nil
        local rawName = type(enemy) == "table" and not DataUtils.IsSecret(enemy) and type(enemy.name) == "string" and DataUtils.Trim(enemy.name) or nil
        if not rawName or rawName == "" then return false end
        -- Use rawget deliberately. MDT locale tables commonly fall back to the
        -- English key through __index; that fallback does not prove the client
        -- actually uses that English unit name.
        local localized = rawget(localeTable, rawName)
        if DataUtils.IsSecret(localized) or type(localized) ~= "string" or DataUtils.Trim(localized) == "" then return false end
      end
    end
  end
  return true
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
  local challengeMapID = type(mapInfo) == "table" and DataUtils.PositiveInteger(mapInfo.mapID) or nil
  if not challengeMapID then challengeMapID = resolveChallengeMapID(dungeonName) end
  local locale=getClientLocale()
  local localeTable = type(legacy.L)=="table" and not DataUtils.IsSecret(legacy.L) and legacy.L or nil
  local markedNamesVerified = markedLegacyNamesVerified(preset, enemyData, locale, localeTable)
  local enemyNameResolver
  if localeTable then
    enemyNameResolver=function(rawName)
      if sourceNamesMatchClientLocale(locale) then return rawName end
      local localized = rawget(localeTable, rawName)
      if type(localized)=="string" and localized~="" and not DataUtils.IsSecret(localized) then return localized end
      return rawName
    end
  end
  return Addon.RouteSnapshot.NormalizePreset(preset, {
    sourceMode="legacy-internal", compatibility=enemyData and "full" or "limited", mdtVersion=state.version, dungeonIndex=dungeonIndex, dungeonName=dungeonName, challengeMapID=challengeMapID, presetIndex=presetIndex, enemyData=enemyData, enemyDataScope=enemyData and "dungeon" or nil,
    enemyNameResolver=enemyNameResolver, clientLocale=locale, targetNameLocaleStatus=markedNamesVerified and (sourceNamesMatchClientLocale(locale) and "verified-client-locale" or "verified-mdt-locale") or "unverified-source-locale",
  })
end

local function readDBOnlySnapshot(api, allowUILoad)
  if type(api) ~= "table" or type(api.GetDB) ~= "function" then return nil, "db-api-unavailable" end
  local db, dbError = safeCall(api.GetDB, api)
  if not db then return nil, dbError or "db-unavailable" end

  local preset, presetError, dungeonIndex, presetIndex = currentPresetFromDB(db)
  local mayLoadUI = allowUILoad == true and not (type(InCombatLockdown) == "function" and InCombatLockdown())

  -- MDT 6.2 keeps route/preset defaults in its load-on-demand UI addon. The public
  -- core DB may therefore be valid while route fields are not populated yet. Load
  -- the UI silently only for an explicit dungeon-session enrichment outside combat,
  -- then re-read the public DB instead of failing permanently on route-db-not-ready.
  if not preset and mayLoadUI and not state.uiLoaded and presetError == "route-db-not-ready" then
    local loaded, loadError = loadMDTUIForRouteData()
    if not loaded then return nil, loadError or presetError end
    installEnemyMetadataHook()
    db, dbError = safeCall(api.GetDB, api)
    if not db then return nil, dbError or "db-unavailable-after-ui-load" end
    preset, presetError, dungeonIndex, presetIndex = currentPresetFromDB(db)
  end
  if not preset then return nil, presetError end

  local liveEnemyData=dungeonIndex and capturedEnemyData[dungeonIndex] or nil
  local hasCapturedEnemyData=capturedActiveDungeonIndex==dungeonIndex and type(liveEnemyData)=="table" and next(liveEnemyData)~=nil
  local cachedEnemyData,cachedNamesVerified,cachedDungeonName,cachedChallengeMapID
  if not hasCapturedEnemyData then
    cachedEnemyData,cachedNamesVerified,cachedDungeonName,cachedChallengeMapID=matchingCachedEnemyData(dungeonIndex)
  end

  -- A valid version/locale/dungeon-bound cache can also carry the active dungeon
  -- identity. Prefer that after /reload so a disabled or unavailable MDT UI layer
  -- does not make an already-known route unverifiable. Load MDT's UI only when
  -- the identity is still missing and the caller explicitly allows enrichment.
  local dungeonName = DataUtils.SafeString(cachedDungeonName, 1024, true)
  local challengeMapID = DataUtils.PositiveInteger(cachedChallengeMapID)
  if not dungeonName and state.uiLoaded and type(api.GetDungeonName) == "function" then
    dungeonName = safeCall(api.GetDungeonName, api, dungeonIndex)
  end
  if not challengeMapID and dungeonName then challengeMapID=resolveChallengeMapID(dungeonName) end

  if mayLoadUI and not state.uiLoaded and not dungeonName then
    local loaded, loadError = loadMDTUIForRouteData()
    if loaded then
      installEnemyMetadataHook()
      local refreshedDB = safeCall(api.GetDB, api)
      if refreshedDB then
        local refreshedPreset, _, refreshedDungeonIndex, refreshedPresetIndex = currentPresetFromDB(refreshedDB)
        if refreshedPreset then preset, dungeonIndex, presetIndex = refreshedPreset, refreshedDungeonIndex, refreshedPresetIndex end
      end
      if type(api.GetDungeonName) == "function" then dungeonName = safeCall(api.GetDungeonName, api, dungeonIndex) end
      if not challengeMapID and dungeonName then challengeMapID=resolveChallengeMapID(dungeonName) end
    else
      addStateWarning("mdt-ui-enrichment-failed", loadError or "mdt-ui-load-failed")
    end
  end

  -- Re-evaluate live/cache data if UI enrichment changed the dungeon selection.
  liveEnemyData=dungeonIndex and capturedEnemyData[dungeonIndex] or nil
  hasCapturedEnemyData=capturedActiveDungeonIndex==dungeonIndex and type(liveEnemyData)=="table" and next(liveEnemyData)~=nil
  if not hasCapturedEnemyData then
    cachedEnemyData,cachedNamesVerified,cachedDungeonName,cachedChallengeMapID=matchingCachedEnemyData(dungeonIndex)
    if not dungeonName then dungeonName=DataUtils.SafeString(cachedDungeonName,1024,true) end
    if not challengeMapID then challengeMapID=DataUtils.PositiveInteger(cachedChallengeMapID) end
  end
  local hasCachedEnemyData=type(cachedEnemyData)=="table" and next(cachedEnemyData)~=nil
  if hasCachedEnemyData and (dungeonName or challengeMapID) then persistCachedDungeonIdentity(dungeonIndex,dungeonName,challengeMapID) end
  local enemyData=hasCapturedEnemyData and liveEnemyData or (hasCachedEnemyData and cachedEnemyData or nil)
  local namesVerified=hasCapturedEnemyData and capturedTargetNamesVerified or (hasCachedEnemyData and cachedNamesVerified or false)
  local compatibility=hasCapturedEnemyData and "route-data+captured-enemy" or (hasCachedEnemyData and "route-data+cached-enemy" or "route-data")
  return Addon.RouteSnapshot.NormalizePreset(preset,{
    sourceMode="db-only",compatibility=compatibility,mdtVersion=state.version,dungeonIndex=dungeonIndex,dungeonName=dungeonName,challengeMapID=challengeMapID,presetIndex=presetIndex,enemyData=enemyData,
    enemyDataScope=hasCapturedEnemyData and "captured-map" or (hasCachedEnemyData and "cached-active-dungeon" or nil), clientLocale=getClientLocale(), targetNameLocaleStatus=enemyData and localeStatus(namesVerified) or nil, expectCloneMetadata=hasCapturedEnemyData,
  })
end

local function bindingDatabase(api, legacy, allowUILoad)
  local db
  if type(api) == "table" and type(api.GetDB) == "function" then db = safeCall(api.GetDB, api) end
  if type(db) ~= "table" and type(legacy) == "table" and type(legacy.GetDB) == "function" then
    db = safeCall(legacy.GetDB, legacy)
  end
  local mayLoadUI = allowUILoad == true and not (type(InCombatLockdown) == "function" and InCombatLockdown())
  if type(db) == "table" and type(db.presets) == "table" then return db end
  if mayLoadUI and not state.uiLoaded then
    local loaded = loadMDTUIForRouteData()
    if loaded then
      installEnemyMetadataHook()
      if type(api) == "table" and type(api.GetDB) == "function" then db = safeCall(api.GetDB, api) end
      if type(db) ~= "table" and type(legacy) == "table" and type(legacy.GetDB) == "function" then
        db = safeCall(legacy.GetDB, legacy)
      end
    end
  end
  return type(db) == "table" and db or nil
end

local function activeChallengeMapID()
  if type(C_ChallengeMode) ~= "table" or type(C_ChallengeMode.GetActiveChallengeMapID) ~= "function" then return nil end
  return DataUtils.PositiveInteger(safeCall(C_ChallengeMode.GetActiveChallengeMapID))
end

local function challengeMapName(challengeMapID)
  challengeMapID = DataUtils.PositiveInteger(challengeMapID)
  if not challengeMapID or type(C_ChallengeMode) ~= "table" or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then return nil end
  return DataUtils.SafeString(safeCall(C_ChallengeMode.GetMapUIInfo, challengeMapID), 1024, true)
end

local function currentBindingDungeonName(binding)
  if type(binding) ~= "table" or DataUtils.IsSecret(binding) then return nil end
  local dungeonIndex = DataUtils.PositiveInteger(binding.dungeonIndex, 1000)
  if not dungeonIndex then return nil end

  local legacy = type(_G.MDT) == "table" and _G.MDT or nil
  if type(legacy) == "table" and type(legacy.dungeonList) == "table" and not DataUtils.IsSecret(legacy.dungeonList) then
    local legacyName = DataUtils.SafeString(legacy.dungeonList[dungeonIndex], 1024, true)
    if legacyName then return legacyName end
  end

  local api = type(_G.MythicDungeonToolsAPI) == "table" and _G.MythicDungeonToolsAPI or nil
  local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() == true
  if type(api) == "table" and type(api.GetDungeonName) ~= "function" and not inCombat and not state.uiLoaded then
    loadMDTUIForRouteData()
    api = type(_G.MythicDungeonToolsAPI) == "table" and _G.MythicDungeonToolsAPI or api
  end
  if type(api) == "table" and type(api.GetDungeonName) == "function" and (state.uiLoaded or not inCombat) then
    local currentName = DataUtils.SafeString(safeCall(api.GetDungeonName, api, dungeonIndex), 1024, true)
    if currentName then return currentName end
  end

  return DataUtils.SafeString(binding.dungeonName, 1024, true)
end

local function bindingForActiveChallengeMap(challengeMapID)
  if not Addon.Database then return nil end
  challengeMapID = DataUtils.PositiveInteger(challengeMapID) or activeChallengeMapID()
  if not challengeMapID then return nil end

  if type(Addon.Database.FindRouteBindingByChallengeMapID) == "function" then
    local binding, bindingError = Addon.Database.FindRouteBindingByChallengeMapID(challengeMapID)
    if binding then return binding, "active-challenge-map" end
    if bindingError and bindingError ~= "route-binding-map-not-found" then return nil, bindingError end
  end

  -- A route can be bound before a future season becomes active. In that case
  -- C_ChallengeMode.GetMapTable may not expose the dungeon yet, so the saved
  -- binding can legitimately have no challengeMapID. Once that dungeon is
  -- active, recover only by an exact, unique client-localized dungeon name.
  -- Never use a binding that already carries a different map ID.
  local activeName = challengeMapName(challengeMapID)
  local wantedName = normalizeDungeonName(activeName)
  if not wantedName or type(Addon.Database.GetRouteBindings) ~= "function" then
    return nil, "active-challenge-map-unbound"
  end

  local match
  for _, binding in pairs(Addon.Database.GetRouteBindings() or {}) do
    if type(binding) == "table" and DataUtils.PositiveInteger(binding.challengeMapID) == nil
      and normalizeDungeonName(currentBindingDungeonName(binding)) == wantedName then
      if match then return nil, "route-binding-name-ambiguous" end
      match = binding
    end
  end
  if not match then return nil, "active-challenge-map-unbound" end

  -- Promote only the in-memory copy for this active session. The persisted
  -- binding remains untouched until the user explicitly binds again, avoiding
  -- an implicit SavedVariables mutation merely from entering a dungeon.
  match.challengeMapID = challengeMapID
  return match, "active-challenge-name"
end

local function selectSavedBinding(api, legacy, allowUILoad)
  if not Addon.Database then return nil end
  local challengeMapID = activeChallengeMapID()
  if challengeMapID then
    local binding, bindingError = bindingForActiveChallengeMap(challengeMapID)
    if binding then return binding, "active-challenge-map" end
    -- An active Mythic+ map is authoritative. Never fall back to whichever
    -- dungeon happens to be selected in MDT, otherwise a saved binding for a
    -- different dungeon could look active during this run.
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

local function routeKeyForPreset(preset, dungeonIndex, presetIndex)
  local snapshot = Addon.RouteSnapshot.NormalizePreset(preset, {
    sourceMode = "route-identity",
    compatibility = "identity-only",
    dungeonIndex = dungeonIndex,
    presetIndex = presetIndex,
  })
  return snapshot and snapshot.routeKey or nil, snapshot
end

local function resolveBoundPreset(db, binding)
  if type(db) ~= "table" or DataUtils.IsSecret(db) or type(binding) ~= "table" then return nil, "bound-route-db-unavailable" end
  local dungeonIndex = DataUtils.PositiveInteger(binding.dungeonIndex)
  local presets = type(db.presets) == "table" and not DataUtils.IsSecret(db.presets) and db.presets[dungeonIndex] or nil
  if type(presets) ~= "table" or DataUtils.IsSecret(presets) then return nil, "bound-route-dungeon-unavailable" end

  local wantedUID = DataUtils.SafeString(binding.presetUID, 120, true)
  if wantedUID then
    for presetIndex, preset in pairs(presets) do
      presetIndex = DataUtils.PositiveInteger(presetIndex)
      if presetIndex and type(preset) == "table" and not DataUtils.IsSecret(preset)
        and type(preset.value) == "table" and not DataUtils.IsSecret(preset.value)
        and DataUtils.SafeString(preset.uid, 120, true) == wantedUID then
        return preset, presetIndex, dungeonIndex
      end
    end
    return nil, "bound-route-uid-not-found"
  end

  local wantedKey = DataUtils.SafeString(binding.routeKey, 120, true)
  local wantedName = DataUtils.SafeString(binding.presetName, 240, true)
  local exactKeyMatches = {}
  local sameNameMatches = {}
  for presetIndex, preset in pairs(presets) do
    presetIndex = DataUtils.PositiveInteger(presetIndex)
    if presetIndex and type(preset) == "table" and not DataUtils.IsSecret(preset)
      and type(preset.value) == "table" and not DataUtils.IsSecret(preset.value) then
      local key = routeKeyForPreset(preset, dungeonIndex, presetIndex)
      local name = DataUtils.SafeString(preset.text or preset.name, 240, true)
      if key == wantedKey then exactKeyMatches[#exactKeyMatches + 1] = { preset, presetIndex, name } end
      if wantedName and name == wantedName then sameNameMatches[#sameNameMatches + 1] = { preset, presetIndex } end
    end
  end
  if #exactKeyMatches == 1 then
    return exactKeyMatches[1][1], exactKeyMatches[1][2], dungeonIndex
  end
  if #exactKeyMatches > 1 then
    local namedExactMatches = {}
    if wantedName then
      for _, match in ipairs(exactKeyMatches) do
        if match[3] == wantedName then namedExactMatches[#namedExactMatches + 1] = match end
      end
    end
    if #namedExactMatches == 1 then
      return namedExactMatches[1][1], namedExactMatches[1][2], dungeonIndex
    end
    return nil, "bound-route-fingerprint-ambiguous"
  end
  if #sameNameMatches == 1 then
    return sameNameMatches[1][1], sameNameMatches[1][2], dungeonIndex
  end
  if #sameNameMatches > 1 then return nil, "bound-route-name-ambiguous" end
  return nil, "bound-route-fingerprint-not-found"
end

local function readBoundSnapshot(api, legacy, binding, allowUILoad)
  local db = bindingDatabase(api, legacy, allowUILoad)
  if not db then return nil, "bound-route-db-unavailable" end
  local preset, presetIndex, dungeonIndex = resolveBoundPreset(db, binding)
  if not preset then return nil, presetIndex end

  local locale = getClientLocale()
  local enemyData, namesVerified, compatibility, enemyDataScope, enemyNameResolver
  local dungeonName = DataUtils.SafeString(currentBindingDungeonName(binding), 1024, true)
    or DataUtils.SafeString(binding.dungeonName, 1024, true)
  local challengeMapID = DataUtils.PositiveInteger(binding.challengeMapID)

  if type(legacy) == "table" then
    enemyData = type(legacy.dungeonEnemies) == "table" and not DataUtils.IsSecret(legacy.dungeonEnemies) and legacy.dungeonEnemies[dungeonIndex] or nil
    dungeonName = dungeonName or (type(legacy.dungeonList) == "table" and not DataUtils.IsSecret(legacy.dungeonList) and legacy.dungeonList[dungeonIndex] or nil)
    local mapInfo = type(legacy.mapInfo) == "table" and not DataUtils.IsSecret(legacy.mapInfo) and legacy.mapInfo[dungeonIndex] or nil
    challengeMapID = challengeMapID or (type(mapInfo) == "table" and DataUtils.PositiveInteger(mapInfo.mapID) or nil)
    local localeTable = type(legacy.L) == "table" and not DataUtils.IsSecret(legacy.L) and legacy.L or nil
    namesVerified = markedLegacyNamesVerified(preset, enemyData, locale, localeTable)
    if localeTable then
      enemyNameResolver = function(rawName)
        if sourceNamesMatchClientLocale(locale) then return rawName end
        local localized = rawget(localeTable, rawName)
        if type(localized) == "string" and localized ~= "" and not DataUtils.IsSecret(localized) then return localized end
        return rawName
      end
    end
    compatibility = enemyData and "bound-route+legacy-enemy" or "bound-route-limited"
    enemyDataScope = enemyData and "dungeon" or nil
  else
    local liveEnemyData = dungeonIndex and capturedEnemyData[dungeonIndex] or nil
    local hasCaptured = capturedActiveDungeonIndex == dungeonIndex and type(liveEnemyData) == "table" and next(liveEnemyData) ~= nil
    local cachedEnemyData, cachedNamesVerified, cachedDungeonName, cachedChallengeMapID
    if not hasCaptured then
      cachedEnemyData, cachedNamesVerified, cachedDungeonName, cachedChallengeMapID = matchingCachedEnemyData(dungeonIndex)
    end
    local hasCached = type(cachedEnemyData) == "table" and next(cachedEnemyData) ~= nil
    enemyData = hasCaptured and liveEnemyData or (hasCached and cachedEnemyData or nil)
    namesVerified = hasCaptured and capturedTargetNamesVerified or (hasCached and cachedNamesVerified or false)
    dungeonName = dungeonName or DataUtils.SafeString(cachedDungeonName, 1024, true)
    challengeMapID = challengeMapID or DataUtils.PositiveInteger(cachedChallengeMapID)
    if not dungeonName and type(api) == "table" and type(api.GetDungeonName) == "function" then
      dungeonName = safeCall(api.GetDungeonName, api, dungeonIndex)
    end
    compatibility = hasCaptured and "bound-route+captured-enemy" or (hasCached and "bound-route+cached-enemy" or "bound-route")
    enemyDataScope = hasCaptured and "captured-map" or (hasCached and "cached-active-dungeon" or nil)
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
    enemyNameResolver = enemyNameResolver,
    clientLocale = locale,
    targetNameLocaleStatus = enemyData and (type(legacy) == "table"
      and (namesVerified and (sourceNamesMatchClientLocale(locale) and "verified-client-locale" or "verified-mdt-locale") or "unverified-source-locale")
      or localeStatus(namesVerified)) or nil,
    expectCloneMetadata = type(legacy) ~= "table" and capturedActiveDungeonIndex == dungeonIndex,
  })
  if not snapshot then return nil, snapshotError end
  if snapshot.routeKey ~= binding.routeKey then
    -- MDT intentionally clears the UID on a newly copied route. For those
    -- common UID-less routes, bind to the unique preset name/slot so editing a
    -- pull does not sever the binding just because the content fingerprint
    -- changed. UID-backed routes remain strict.
    if binding.presetUID then return nil, "bound-route-identity-changed" end
    local boundName = DataUtils.SafeString(binding.presetName, 240, true)
    if not boundName or snapshot.presetName ~= boundName then return nil, "bound-route-identity-changed" end
  end
  return snapshot
end

local function registerUIInitializer(api)
  if initializerRegistered or type(api) ~= "table" or type(api.RegisterUIInitializer) ~= "function" then return end
  initializerRegistered = true
  local ok = pcall(api.RegisterUIInitializer, api, function()
    if uiInitializerRefreshScheduled then return end
    uiInitializerRefreshScheduled = true
    local function refreshAfterAttach()
      uiInitializerRefreshScheduled = false
      installEnemyMetadataHook()
      Adapter:Refresh("mdt-ui-initialized")
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
      C_Timer.After(0, refreshAfterAttach)
    else
      refreshAfterAttach()
    end
  end)
  if not ok then initializerRegistered = false end
end

function Adapter:Initialize()
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
  if state.uiLoaded then installEnemyMetadataHook() end
  state.version = versionRaw
  state.versionStatus = classifyVersion(parsedVersion)

  if not state.installed then
    state.lastError = "mdt-not-installed"
    return nil, state.lastError
  end

  if api then registerUIInitializer(api) end

  local snapshot, snapshotError
  local binding
  if not options.ignoreBinding then binding = selectSavedBinding(api, legacy, options.allowUILoad == true) end
  if binding then
    state.activeBinding = DataUtils.DeepCopy(binding)
    snapshot, snapshotError = readBoundSnapshot(api, legacy, binding, options.allowUILoad == true)
    if snapshot then
      state.mode = "bound-route"
      state.compatibility = snapshot.compatibility or "bound-route"
    else
      state.mode = "bound-route-unavailable"
      state.compatibility = "unavailable"
      state.lastError = snapshotError or "bound-route-unavailable"
      return nil, state.lastError
    end
  end
  if not snapshot and api and type(api.GetCurrentRouteSnapshot) == "function" then
    snapshot, snapshotError = readPublicSnapshot(api)
    if snapshot then
      state.mode = "public-snapshot"
      state.compatibility = "full"
    else
      addStateWarning("public-snapshot-failed", snapshotError)
    end
  end

  if not snapshot and legacy then
    snapshot, snapshotError = readLegacySnapshot(legacy)
    if snapshot then
      state.mode = "legacy-internal"
      state.compatibility = snapshot.compatibility or "limited"
    else
      addStateWarning("legacy-snapshot-failed", snapshotError)
    end
  end

  if not snapshot and api then
    snapshot, snapshotError = readDBOnlySnapshot(api, options.allowUILoad == true)
    if snapshot then
      state.mode = "db-only"
      state.compatibility = snapshot.compatibility or "route-data"
      if state.compatibility ~= "route-data+captured-enemy" and state.compatibility ~= "route-data+cached-enemy" then
        addStateWarning("enemy-metadata-unavailable", "MDT route data is available, but enemy identity metadata is not available yet.")
      elseif snapshot.targetNameLocaleStatus == "unverified-source-locale" then
        addStateWarning("target-name-locale-unverified", "MDT enemy source names are not verified for the active client locale.")
      end
    else
      addStateWarning("db-snapshot-failed", snapshotError)
    end
  end

  if snapshot then
    state.snapshot = snapshot
    if state.versionStatus == "too-old" then
      state.snapshot = nil
      state.compatibility = "unavailable"
      state.lastError = "mdt-version-too-old"
      return nil, state.lastError
    end
    if state.versionStatus == "compatible-range" then
      addStateWarning("unverified-mdt-version", state.version)
    elseif state.versionStatus == "untested-newer" then
      addStateWarning("untested-mdt-version", state.version)
    end
    return self:GetSnapshot()
  end

  state.mode = state.loaded and "waiting-route-data" or "installed-not-loaded"
  state.compatibility = "unavailable"
  state.lastError = snapshotError or "route-data-unavailable"
  return nil, state.lastError
end

function Adapter:GetRouteBinding(dungeonIndex)
  dungeonIndex = DataUtils.PositiveInteger(dungeonIndex, 1000)
  if dungeonIndex and Addon.Database and type(Addon.Database.GetRouteBinding) == "function" then
    return Addon.Database.GetRouteBinding(dungeonIndex)
  end
  local challengeMapID = activeChallengeMapID()
  if challengeMapID then
    local binding = bindingForActiveChallengeMap(challengeMapID)
    return binding
  end
  if state.activeBinding then return DataUtils.DeepCopy(state.activeBinding) end
  local snapshotDungeon = state.snapshot and DataUtils.PositiveInteger(state.snapshot.dungeonIndex, 1000) or nil
  if snapshotDungeon and Addon.Database and type(Addon.Database.GetRouteBinding) == "function" then
    return Addon.Database.GetRouteBinding(snapshotDungeon)
  end
  return nil
end

function Adapter:GetRouteBindings()
  return Addon.Database and type(Addon.Database.GetRouteBindings) == "function" and Addon.Database.GetRouteBindings() or {}
end

function Adapter:BindCurrentRoute()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "in-combat" end
  local snapshot, snapshotError = self:Refresh("bind-current-route", { ignoreBinding = true, allowUILoad = true })
  if not snapshot then return nil, snapshotError or "route-unavailable" end
  if not snapshot.routeKey or not snapshot.dungeonIndex then return nil, "route-identity-unavailable" end
  local liveChallengeMapID = activeChallengeMapID()
  local routeChallengeMapID = DataUtils.PositiveInteger(snapshot.challengeMapID)
  if liveChallengeMapID then
    if not routeChallengeMapID then
      local activeName = normalizeDungeonName(challengeMapName(liveChallengeMapID))
      local routeName = normalizeDungeonName(snapshot.dungeonName)
      if not activeName or not routeName or activeName ~= routeName then return nil, "bind-route-active-dungeon-unverified" end
      routeChallengeMapID = liveChallengeMapID
    end
    if routeChallengeMapID ~= liveChallengeMapID then return nil, "bind-route-active-dungeon-mismatch" end
  end
  local binding = {
    routeKey = snapshot.routeKey,
    presetUID = snapshot.presetUID,
    presetName = snapshot.presetName,
    presetIndex = snapshot.presetIndex,
    dungeonIndex = snapshot.dungeonIndex,
    dungeonName = snapshot.dungeonName,
    challengeMapID = routeChallengeMapID,
    boundFingerprint = snapshot.fingerprint,
    mdtVersion = snapshot.mdtVersion or state.version,
  }
  local previous = Addon.Database.GetRouteBinding and Addon.Database.GetRouteBinding(binding.dungeonIndex) or nil
  local saved, saveError = Addon.Database.SetRouteBinding(binding)
  if not saved then return nil, saveError or "route-binding-save-failed" end
  local rebound, reboundError = self:Refresh("route-bound", { allowUILoad = true })
  if not rebound then
    if previous then
      Addon.Database.SetRouteBinding(previous)
    else
      Addon.Database.ClearRouteBinding(binding.dungeonIndex)
    end
    self:Refresh("route-bind-rollback", { allowUILoad = true })
    return nil, reboundError or "bound-route-refresh-failed"
  end
  return self:GetRouteBinding(binding.dungeonIndex)
end

function Adapter:ClearRouteBinding(dungeonIndex)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "in-combat" end
  dungeonIndex = DataUtils.PositiveInteger(dungeonIndex, 1000)
  if not dungeonIndex then
    local liveChallengeMapID = activeChallengeMapID()
    if liveChallengeMapID then
      local binding = bindingForActiveChallengeMap(liveChallengeMapID)
      dungeonIndex = binding and DataUtils.PositiveInteger(binding.dungeonIndex, 1000) or nil
      if not dungeonIndex then return nil, "active-dungeon-route-unbound" end
    end
  end
  dungeonIndex = dungeonIndex
    or (state.activeBinding and DataUtils.PositiveInteger(state.activeBinding.dungeonIndex, 1000))
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
  local binding = Addon.Database and type(Addon.Database.GetRouteBinding) == "function" and Addon.Database.GetRouteBinding(dungeonIndex) or nil
  local result = {}
  for presetIndex, preset in pairs(presets) do
    presetIndex = DataUtils.PositiveInteger(presetIndex)
    if presetIndex and type(preset) == "table" and not DataUtils.IsSecret(preset)
      and type(preset.value) == "table" and not DataUtils.IsSecret(preset.value)
      and type(preset.value.pulls) == "table" and not DataUtils.IsSecret(preset.value.pulls) then
      local routeKey, identity = routeKeyForPreset(preset, dungeonIndex, presetIndex)
      if routeKey and identity then
        result[#result + 1] = {
          routeKey = routeKey,
          presetUID = identity.presetUID,
          presetName = identity.presetName or ("Route "..tostring(presetIndex)),
          presetIndex = presetIndex,
          dungeonIndex = dungeonIndex,
          pullCount = #(identity.pulls or {}),
          current = type(db.currentPreset) == "table" and tonumber(db.currentPreset[dungeonIndex]) == presetIndex or false,
          bound = binding and binding.dungeonIndex == dungeonIndex and (
            (binding.presetUID and identity.presetUID == binding.presetUID)
            or (not binding.presetUID and binding.presetName == identity.presetName)
          ) or false,
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
  return {
    status = snapshot.nativeAssignmentsAvailable == true and "ready" or "ready-limited",
    routeKey = snapshot.routeKey,
    action = "snapshot-refreshed",
  }
end

function Adapter:BuildMarkerPlan(options)
  local snapshot = self:GetSnapshot()
  if not snapshot then
    return nil, { { severity = "error", code = state.lastError or "route-unavailable", path = "mdt" } }
  end
  local global = Addon.Database.GetGlobal and Addon.Database.GetGlobal() or {}
  local requested = type(options) == "table" and options or {}
  local preserveExistingMarkers = requested.preserveExistingMarkers
  if preserveExistingMarkers == nil then preserveExistingMarkers = global.preserveExistingMarkers ~= false end
  local maxBatches = requested.maxBatches
  if maxBatches == nil then maxBatches = self:GetRouteBinding() and 3 or 2 end
  return Addon.MarkerPlanner.Build(snapshot, {
    preserveExistingMarkers = preserveExistingMarkers,
    maxBatches = maxBatches,
  })
end

function Adapter:ValidateActiveRoute()
  local plan, findings = self:BuildMarkerPlan()
  findings = findings or {}
  local snapshot = self:GetSnapshot()
  if Addon.MDTFocusMarkerBridge and type(Addon.MDTFocusMarkerBridge.GetFindings) == "function" then
    for _, item in ipairs(Addon.MDTFocusMarkerBridge:GetFindings(snapshot) or {}) do findings[#findings + 1] = item end
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
    database = Addon.Database.GetState and Addon.Database.GetState() or nil,
    snapshotSummary = state.snapshot and {
      dungeonIndex = state.snapshot.dungeonIndex, dungeonName = state.snapshot.dungeonName,
      presetName = state.snapshot.presetName, pullCount = #(state.snapshot.pulls or {}),
      nativeAssignmentsAvailable = state.snapshot.nativeAssignmentsAvailable == true,
    } or nil,
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
    capturedEnemyDungeonCount=(function() local count=0 for _ in pairs(capturedEnemyData) do count=count+1 end return count end)(),
    capturedActiveDungeonIndex=capturedActiveDungeonIndex,
    metadataCacheAvailable=Addon.Database and type(Addon.Database.GetEnemyMetadataCache)=="function" and Addon.Database.GetEnemyMetadataCache()~=nil or false,
    routeBinding=self:GetRouteBinding(),
    routeBindingCount=(function() local count=0 for _ in pairs(self:GetRouteBindings()) do count=count+1 end return count end)(),
    boundRoute=self:GetRouteBinding()~=nil,
    lastRefreshReason=state.lastRefreshReason,
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
  for _, warning in ipairs(status.warnings or {}) do
    Addon.Chat(("Warning: %s%s"):format(tostring(warning.code), warning.detail and " - "..tostring(warning.detail) or ""))
  end
end

function Adapter:PrintRouteSummary()
  local snapshot = self:GetSnapshot()
  if not snapshot then
    Addon.Chat("No normalized MDT route is currently available.")
    self:PrintStatus()
    return
  end

  local enemyCount, cloneCount = 0, 0
  for _, pull in ipairs(snapshot.pulls) do
    enemyCount = enemyCount + #pull.enemies
    for _, enemy in ipairs(pull.enemies) do cloneCount = cloneCount + #enemy.clones end
  end

  Addon.Chat(("Route: %s; dungeon %s; pulls %d; enemy groups %d; clones %d"):format(
    tostring(snapshot.presetName or snapshot.presetUID or "unnamed"),
    tostring(snapshot.dungeonIndex or "unknown"),
    #snapshot.pulls,
    enemyCount,
    cloneCount
  ))
  Addon.Chat("Fingerprint: "..tostring(snapshot.fingerprint))
  Addon.Chat("Source mode: "..tostring(snapshot.sourceMode).." / "..tostring(snapshot.compatibility))
  for _, warning in ipairs(snapshot.warnings or {}) do
    Addon.Chat(("Route warning: %s%s"):format(tostring(warning.code), warning.detail and " - "..tostring(warning.detail) or ""))
  end
end

Adapter.ParseVersion = parseVersion
Adapter.ClassifyVersion = classifyVersion
