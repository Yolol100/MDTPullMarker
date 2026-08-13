local _, Addon = ...

local Bridge = {}
Addon.MDTFocusMarkerBridge = Bridge

local constants = Addon.Constants or {}
local FOCUS_KEYBIND_COMMAND = "CLICK MDTFocusMarkerButton:LeftButton"
local PULL_KEYBIND_COMMAND = "CLICK "..tostring(constants.SmartButtonName or "MDTPullMarkerSmartButton")..":LeftButton"
local DEFAULT_FOCUS_MACRO_NAME = "MDTFocusMarker"
local PULL_MACRO_NAME = constants.SmartMacroName or "MDTPM1"
local PULL_MACRO_NAME2 = constants.SmartMacroName2 or "MDTPM2"
local MARKER_NAMES = constants.MarkerNames or {}
local state = { available = false, status = "unavailable", severity = "info", code = "mdt-focus-marker-unavailable", message = "MDT Focus Marker is unavailable.", lastError = nil }

local function copy(value) if Addon.DataUtils and Addon.DataUtils.DeepCopy then return Addon.DataUtils.DeepCopy(value) end return value end
local function safeCall(api, ...)
  if type(api) ~= "function" then return nil, "unavailable" end
  local ok, first, second, third = pcall(api, ...); if not ok then return nil, tostring(first) end
  if Addon.IsSecret and Addon.IsSecret(first) then return nil, "secret" end
  if Addon.IsSecret and Addon.IsSecret(second) then second = nil end; if Addon.IsSecret and Addon.IsSecret(third) then third = nil end
  return first, second, third
end
local function refreshNativeFocusAction()
  local legacy = _G.MDT
  if type(legacy) == "table" and type(legacy.FocusMarker_RefreshAction) == "function" then local ok, refreshError = pcall(legacy.FocusMarker_RefreshAction, legacy) if ok then return true, "legacy-focus-refresh" end return nil, "native-focus-refresh-failed:"..tostring(refreshError) end
  return nil, "native-focus-refresh-unavailable"
end
local function getMDTDatabase()
  local api = _G.MythicDungeonToolsAPI
  if type(api) == "table" and type(api.GetDB) == "function" then local value, callError = safeCall(api.GetDB, api) if type(value) == "table" then return value, "public-api" end if callError and callError ~= "unavailable" then return nil, nil, "public-db-read-failed:"..tostring(callError) end end
  local legacy = _G.MDT
  if type(legacy) == "table" and type(legacy.GetDB) == "function" then local value, callError = safeCall(legacy.GetDB, legacy) if type(value) == "table" then return value, "legacy-api" end if callError and callError ~= "unavailable" then return nil, nil, "legacy-db-read-failed:"..tostring(callError) end end
  local saved = _G.MythicDungeonToolsDB; if type(saved) == "table" then if type(saved.global) == "table" then return saved.global, "saved-variables-global" end return saved, "saved-variables" end
  return nil, nil, "mdt-database-unavailable"
end
local function normalizeMarker(value) if Addon.IsSecret and Addon.IsSecret(value) then return nil end value = tonumber(value) if value and value >= 1 and value <= 8 and value % 1 == 0 then return value end end
local function markerList(set) local result = {} for marker = 1, 8 do if set[marker] then result[#result + 1] = marker end end return result end
local function differenceMarkerList(left, right) local result = {} for marker = 1, 8 do if left and left[marker] and not (right and right[marker]) then result[#result + 1] = marker end end return result end
local function unusedMarkerList(routeSet, focusSet) local result = {} for marker = 1, 8 do if not (routeSet and routeSet[marker]) and not (focusSet and focusSet[marker]) then result[#result + 1] = marker end end return result end
local function markerNames(list) local result = {} for _, marker in ipairs(list or {}) do result[#result + 1] = MARKER_NAMES[marker] or tostring(marker) end return table.concat(result, ", ") end
local function keyList(command)
  if type(GetBindingKey) ~= "function" then return {}, "binding-api-unavailable" end
  local ok, key1, key2 = pcall(GetBindingKey, command); if not ok then return {}, "binding-read-failed:"..tostring(key1) end
  if Addon.IsSecret and (Addon.IsSecret(key1) or Addon.IsSecret(key2)) then return {}, "binding-read-secret" end
  local result, seen = {}, {}; for index = 1, 2 do local key = index == 1 and key1 or key2 if type(key) == "string" and key ~= "" and not seen[key] then seen[key] = true result[#result + 1] = key end end; table.sort(result); return result
end
local function intersects(left, right) local overlap = {} for key in pairs(left or {}) do if right and right[key] then overlap[key] = true end end return overlap end
local function keyIntersection(left, right) local lookup, result = {}, {} for _, key in ipairs(left or {}) do lookup[key] = true end for _, key in ipairs(right or {}) do if lookup[key] then result[#result + 1] = key end end table.sort(result) return result end
local function macroStatus(name)
  local result = { name = name, exists = false, index = nil, readable = true }
  if type(name) ~= "string" or name == "" or type(GetMacroIndexByName) ~= "function" then return result end
  local index, indexError = safeCall(GetMacroIndexByName, name); if indexError and indexError ~= "unavailable" then result.readable = false result.error = indexError return result end
  if Addon.IsSecret and Addon.IsSecret(index) then result.readable = false result.error = "secret-macro-index" return result end
  index = tonumber(index)
  if index and index > 0 then result.exists, result.index = true, index if type(GetMacroInfo) == "function" then local ok, macroName, icon, body = pcall(GetMacroInfo, index) if not ok then result.readable = false result.error = "macro-info-read-failed:"..tostring(macroName) elseif not (Addon.IsSecret and (Addon.IsSecret(macroName) or Addon.IsSecret(icon) or Addon.IsSecret(body))) then result.name, result.icon, result.body = macroName or name, icon, body else result.readable = false result.error = "secret-macro-info" end end end
  return result
end
local function collectRouteMarkers(snapshot)
  local all, current = {}, {}; local runtimeState = Addon.RuntimeController and Addon.RuntimeController.GetState and Addon.RuntimeController:GetState() or nil; local currentPullIndex = runtimeState and tonumber(runtimeState.currentPullIndex) or (snapshot and tonumber(snapshot.currentPull)); local plan
  if snapshot and Addon.MarkerPlanner and type(Addon.MarkerPlanner.Build) == "function" then local global = Addon.Database and Addon.Database.GetGlobal and Addon.Database.GetGlobal() or {}; local ok, built = pcall(Addon.MarkerPlanner.Build, snapshot, { preserveExistingMarkers = global.preserveExistingMarkers ~= false }) if ok and type(built) == "table" then plan = built end end
  if plan then for _, pull in ipairs(plan.pulls or {}) do local pullSet = tonumber(pull.index) == currentPullIndex and current or nil for _, assignment in ipairs(pull.assignments or {}) do local marker = normalizeMarker(assignment.marker) if marker then all[marker] = true if pullSet then pullSet[marker] = true end end end end return all, current end
  for _, pull in ipairs((snapshot and snapshot.pulls) or {}) do local pullSet = tonumber(pull.index) == currentPullIndex and current or nil for _, enemy in ipairs(pull.enemies or {}) do for _, clone in ipairs(enemy.clones or {}) do local marker = normalizeMarker(clone.marker) if marker then all[marker] = true if pullSet then pullSet[marker] = true end end end end end
  return all, current
end
local function collectFocusMarkers(settings)
  local result, owners = {}, {}; local ownMarker = normalizeMarker(settings and settings.lastMarker); if ownMarker then result[ownMarker] = true end
  local assignments = type(settings and settings.assignments) == "table" and settings.assignments or {}; for playerName, markerValue in pairs(assignments) do local marker = normalizeMarker(markerValue) if marker then result[marker] = true owners[marker] = owners[marker] or {} owners[marker][#owners[marker] + 1] = tostring(playerName) end end
  for _, names in pairs(owners) do table.sort(names) end; return result, ownMarker, owners
end
local function buildMessage(result)
  if result.macroNameConflict then return "MDT Focus Marker and MDT Pull Marker use the same macro name. Change the Focus Marker macro name before creating MDTPM1/MDTPM2." end
  if #result.bindingOverlap > 0 then return "Both marker actions use the same key: "..table.concat(result.bindingOverlap, ", ")..". Assign a different key to each action." end
  if result.nativePreserveExisting == false then return "MDT Focus Marker may overwrite existing target markers. Enable 'Don't overwrite existing target markers'." end
  if result.pullPreserveExisting == false then return "MDT Pull Marker may overwrite existing target markers. Enable preserve-existing markers unless the route intentionally needs priority." end
  if #result.currentPullOverlap > 0 then local free = #result.availableMarkers > 0 and (" Fully free: "..markerNames(result.availableMarkers)..".") or " No markers are completely free." return "The current pull and MDT Focus Marker share icons "..markerNames(result.currentPullOverlap)..". This is only safe when both actions intentionally target the same mob; otherwise WoW moves the icon."..free end
  if #result.routeOverlap > 0 then local free = #result.availableMarkers > 0 and (" Fully free: "..markerNames(result.availableMarkers)..".") or " No markers are completely free." return "The route and MDT Focus Marker share icons "..markerNames(result.routeOverlap)..". Plan which system uses each icon to prevent unintended marker movement."..free end
  if result.focusActionActive then local suffix = result.actionBarBindingUnverifiable and " Manually verify that the two action-bar macros are not bound to the same key." or "" return "Cooperation is safe: separate actions and no detected marker-icon conflict."..suffix end
  if result.focusFeatureConfigured then return "MDT Focus Marker contains group assignments, but your own marker action is not active yet. Pull Marker remains usable independently." end
  return "MDT Focus Marker is present but not actively configured. MDT Pull Marker can be used independently."
end

function Bridge:Refresh(snapshot)
  local database, sourceMode, databaseError = getMDTDatabase(); local settings = database and database.focusMarker
  if type(settings) ~= "table" then state = { available = false, status = "route-only", severity = "info", code = "mdt-focus-marker-unavailable", message = "MDT Focus Marker is unavailable in this MDT version or has not loaded yet.", sourceMode = sourceMode, lastError = databaseError, focusMarkers = {}, routeMarkers = {}, currentPullMarkers = {}, routeOverlap = {}, currentPullOverlap = {}, bindingOverlap = {} } return copy(state) end
  if not snapshot and Addon.MDT and type(Addon.MDT.GetSnapshot) == "function" then snapshot = Addon.MDT:GetSnapshot() end
  local routeSet, currentPullSet = collectRouteMarkers(snapshot); local focusSet, ownFocusMarker, markerOwners = collectFocusMarkers(settings); local routeOverlapSet = intersects(routeSet, focusSet); local currentOverlapSet = intersects(currentPullSet, focusSet)
  local focusKeys, focusKeyError = keyList(FOCUS_KEYBIND_COMMAND); local pullKeys, pullKeyError = keyList(PULL_KEYBIND_COMMAND); local bindingOverlap = keyIntersection(focusKeys, pullKeys)
  local focusMacroName = type(settings.macroName) == "string" and settings.macroName ~= "" and settings.macroName or DEFAULT_FOCUS_MACRO_NAME; local focusMacro = macroStatus(focusMacroName); local pullMacro = macroStatus(PULL_MACRO_NAME); local pullMacro2 = macroStatus(PULL_MACRO_NAME2); local useMacro = settings.useMacro == true
  local focusActionActive = ownFocusMarker ~= nil and ((useMacro and focusMacro.exists) or (not useMacro and #focusKeys > 0)); local focusAssignments = type(settings.assignments) == "table" and settings.assignments or {}; local groupAssignmentsPresent = next(focusAssignments) ~= nil; local pullGlobal = Addon.Database and Addon.Database.GetGlobal and Addon.Database.GetGlobal() or {}
  local result = { available = true, sourceMode = sourceMode, status = "coordinated", severity = "info", code = "cooperation-safe", lastError = databaseError or focusKeyError or pullKeyError or focusMacro.error or pullMacro.error or pullMacro2.error,
    focusKeyError = focusKeyError, pullKeyError = pullKeyError, focusActionActive = focusActionActive, focusFeatureConfigured = ownFocusMarker ~= nil or groupAssignmentsPresent, groupAssignmentsPresent = groupAssignmentsPresent, useMacro = useMacro,
    focusMacro = focusMacro, pullMacro = pullMacro, pullMacro2 = pullMacro2, pullMacros = { pullMacro, pullMacro2 }, focusMacroName = focusMacroName,
    macroNameConflict = focusMacroName:lower() == PULL_MACRO_NAME:lower() or focusMacroName:lower() == PULL_MACRO_NAME2:lower(), focusKeys = focusKeys, pullKeys = pullKeys, bindingOverlap = bindingOverlap,
    focusMarkers = markerList(focusSet), ownFocusMarker = ownFocusMarker, routeMarkers = markerList(routeSet), currentPullMarkers = markerList(currentPullSet), routeOverlap = markerList(routeOverlapSet), currentPullOverlap = markerList(currentOverlapSet), availableMarkers = unusedMarkerList(routeSet, focusSet), markerOwners = markerOwners,
    routeMarkersWithoutFocusAssignment = differenceMarkerList(routeSet, focusSet), focusMarkersOutsideRoute = differenceMarkerList(focusSet, routeSet), ownFocusMarkerInCurrentPull = ownFocusMarker and currentPullSet[ownFocusMarker] == true or false,
    actionBarBindingUnverifiable = useMacro and focusMacro.exists and (pullMacro.exists or pullMacro2.exists), nativePreserveExisting = settings.preserveExistingTargetMarkers ~= false, pullPreserveExisting = pullGlobal.preserveExistingMarkers ~= false }
  if result.macroNameConflict then result.status, result.severity, result.code = "conflict", "error", "focus-macro-name-conflict"
  elseif #result.bindingOverlap > 0 then result.status, result.severity, result.code = "conflict", "error", "focus-keybind-conflict"
  elseif result.nativePreserveExisting == false then result.status, result.severity, result.code = "attention", "warning", "focus-overwrite-enabled"
  elseif result.pullPreserveExisting == false then result.status, result.severity, result.code = "attention", "warning", "pull-overwrite-enabled"
  elseif #result.currentPullOverlap > 0 then result.status, result.severity, result.code = "attention", "warning", "focus-current-pull-overlap"
  elseif #result.routeOverlap > 0 then result.status, result.severity, result.code = "attention", "warning", "focus-route-overlap"
  elseif not result.focusActionActive then result.status, result.severity, result.code = "route-only", "info", "focus-action-inactive" end
  result.message = buildMessage(result); state = result; return copy(state)
end
function Bridge:GetStatus() return copy(state) end
function Bridge:GetFindings(snapshot)
  local current = self:Refresh(snapshot); local findings = {}
  if current.macroNameConflict then findings[#findings + 1] = { severity = "warning", code = "focus-macro-name-conflict", path = "integration.focusMarker.macroName" } end
  if current.bindingOverlap and #current.bindingOverlap > 0 then findings[#findings + 1] = { severity = "warning", code = "focus-keybind-conflict", path = "integration.focusMarker.keybind" } end
  if current.currentPullOverlap and #current.currentPullOverlap > 0 then findings[#findings + 1] = { severity = "warning", code = "focus-current-pull-overlap", path = "integration.focusMarker.assignments" } elseif current.routeOverlap and #current.routeOverlap > 0 then findings[#findings + 1] = { severity = "warning", code = "focus-route-overlap", path = "integration.focusMarker.assignments" } end
  if current.nativePreserveExisting == false then findings[#findings + 1] = { severity = "warning", code = "focus-overwrite-enabled", path = "integration.focusMarker.preserveExistingTargetMarkers" } end
  if current.pullPreserveExisting == false then findings[#findings + 1] = { severity = "warning", code = "pull-overwrite-enabled", path = "global.preserveExistingMarkers" } end
  return findings
end
function Bridge:ApplySafeDefaults()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "in-combat" end
  local database, _, databaseError = getMDTDatabase(); if type(database) ~= "table" or type(database.focusMarker) ~= "table" then return nil, databaseError or "focus-settings-unavailable" end
  if not (Addon.Database and type(Addon.Database.SetGlobal) == "function") then return nil, "pull-settings-unavailable" end
  local updated, updateError = Addon.Database.SetGlobal("preserveExistingMarkers", true); if not updated then return nil, "pull-preserve-update-failed:"..tostring(updateError) end
  database.focusMarker.preserveExistingTargetMarkers = true
  local warnings = {}; local nativeRefreshed, nativeRefreshError = refreshNativeFocusAction(); if not nativeRefreshed then warnings[#warnings + 1] = tostring(nativeRefreshError)..": open Focus Marker or reload before use" end
  if Addon.MarkerExecutor then local applied, secureError = Addon.MarkerExecutor:ApplySecureConfiguration("focus-cooperation-safe-defaults") if applied == false and secureError ~= "button-unavailable" then warnings[#warnings + 1] = "secure:"..tostring(secureError) end end
  if Addon.MarkerExecutor then local refreshed, macroError = Addon.MarkerExecutor:RefreshSmartMacro("focus-cooperation-safe-defaults") if not refreshed and macroError ~= "macro-missing" and macroError ~= "macro-api-unavailable" then warnings[#warnings + 1] = "macro:"..tostring(macroError) end end
  local current = self:Refresh(); current.applyWarnings = warnings; state.applyWarnings = copy(warnings); return current
end
function Bridge:PrintStatus()
  local current = self:Refresh()
  if Addon.Chat then Addon.Chat("MDT Focus Marker cooperation: "..tostring(current.status).." — "..tostring(current.message)); if current.focusMarkers and #current.focusMarkers > 0 then Addon.Chat("Focus icons: "..markerNames(current.focusMarkers)) end; if current.routeMarkers and #current.routeMarkers > 0 then Addon.Chat("Route icons: "..markerNames(current.routeMarkers)) end; if current.routeMarkersWithoutFocusAssignment and #current.routeMarkersWithoutFocusAssignment > 0 then Addon.Chat("Route icons without Focus Marker assignment: "..markerNames(current.routeMarkersWithoutFocusAssignment)) end; if current.availableMarkers and #current.availableMarkers > 0 then Addon.Chat("Fully free icons: "..markerNames(current.availableMarkers)) end; if current.applyWarnings and #current.applyWarnings > 0 then Addon.Chat("Apply warnings: "..table.concat(current.applyWarnings, ", ")) end end
  return current
end
