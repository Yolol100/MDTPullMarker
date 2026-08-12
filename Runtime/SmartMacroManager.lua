local _, Addon = ...

local Factory = {}
Addon.SmartMacroManager = Factory

local MarkerMacro = Addon.MarkerMacro
local Constants = Addon.Constants or {}
local DEFAULT_BUTTON_NAME = Constants.SmartButtonName or "MDTPullMarkerSmartButton"
local DEFAULT_MACRO_NAMES = {
  Constants.SmartMacroName or "MDTPM1",
  Constants.SmartMacroName2 or "MDTPM2",
}
local ICON_PATH = "Interface/TargetingFrame/UI-RaidTargetingIcon_8"
local ICON_FALLBACK = 134400
local LEGACY_SAFE_IDLE_MACRO = MarkerMacro.LEGACY_SAFE_IDLE_MACRO
local ROUTE_MACRO_PATTERN = "^MPM%d%d%d[ABC]$"

local Manager = {}
Manager.__index = Manager

local function isSecret(value)
  return Addon.IsSecret and Addon.IsSecret(value) or false
end

local function accountMacroLimit()
  local rawLimit = _G.MAX_ACCOUNT_MACROS
  if isSecret(rawLimit) then return nil end
  local limit = tonumber(rawLimit)
  if not limit or limit < 1 or limit % 1 ~= 0 then return nil end
  return limit
end

local function safeMacroRead(api, errorCode, ...)
  if type(api) ~= "function" then return nil, errorCode..":unavailable" end
  local ok, first, second, third = pcall(api, ...)
  if not ok then return nil, errorCode..":"..tostring(first) end
  if isSecret(first) or isSecret(second) or isSecret(third) then return nil, errorCode..":secret" end
  return first, second, third
end

local function readMacroCounts(accountLimit)
  local accountCount, characterCount = safeMacroRead(GetNumMacros, "macro-count-read-failed")
  if accountCount == nil then return nil, nil, characterCount or "macro-count-read-failed" end
  accountCount = tonumber(accountCount)
  characterCount = tonumber(characterCount)
  if not accountCount or not characterCount
    or accountCount < 0 or characterCount < 0
    or accountCount % 1 ~= 0 or characterCount % 1 ~= 0
    or (accountLimit and accountCount > accountLimit)
  then
    return nil, nil, "macro-count-invalid"
  end
  return accountCount, characterCount
end

local function protectedMacroCall(api, ...)
  if type(api) ~= "function" then return nil, "macro-api-unavailable" end
  local ok, result = pcall(api, ...)
  if not ok then return nil, tostring(result) end
  if isSecret(result) then return nil, "macro-api-returned-secret" end
  if not result or tonumber(result) == 0 then return nil, "macro-api-returned-no-index" end
  return tonumber(result) or result
end

function Factory:Create(options)
  options = type(options) == "table" and options or {}
  assert(type(options.desiredBody) == "function", "SmartMacroManager requires desiredBody")
  assert(type(options.dungeonSessionActive) == "function", "SmartMacroManager requires dungeonSessionActive")
  return setmetatable({
    desiredBody = options.desiredBody,
    dungeonSessionActive = options.dungeonSessionActive,
    log = type(options.log) == "function" and options.log or function() end,
    buttonName = options.buttonName or DEFAULT_BUTTON_NAME,
    macroNames = options.macroNames or DEFAULT_MACRO_NAMES,
    pendingRefresh = false,
  }, Manager)
end

function Manager:MarkPending()
  self.pendingRefresh = true
end

function Manager:IsPending()
  return self.pendingRefresh == true
end

function Manager:GetMacroName(batchIndex)
  return self.macroNames[tonumber(batchIndex) or 1]
end

function Manager:GetSmartMacroIcon()
  if type(GetFileIDFromPath) == "function" then
    local ok, fileID = pcall(GetFileIDFromPath, ICON_PATH)
    fileID = ok and not isSecret(fileID) and tonumber(fileID) or nil
    if fileID and fileID ~= 0 then return fileID end
  end
  return ICON_FALLBACK
end

function Manager:ManagedMacroIconMatches(icon)
  local expectedIcon = tonumber(self:GetSmartMacroIcon())
  local observedIcon = tonumber(icon)
  return expectedIcon and observedIcon and expectedIcon == observedIcon or false
end

function Manager:IsRecognizedManagedBody(body, icon)
  -- Reserved names alone never prove ownership. Require both a recognized body
  -- and the dedicated addon icon before editing or deleting a macro.
  if not self:ManagedMacroIconMatches(icon) then return false end
  if MarkerMacro.IsRecognizedBody(body) then return true end
  return body == LEGACY_SAFE_IDLE_MACRO
end

function Manager:EditManagedMacro(index, body, expectedName)
  if type(EditMacro) ~= "function" then return nil, "edit-macro-unavailable" end
  local ok, editResult = pcall(EditMacro, index, nil, self:GetSmartMacroIcon(), body)
  if not ok then return nil, "edit-macro-failed:"..tostring(editResult) end
  if isSecret(editResult) then return nil, "edit-macro-returned-secret" end

  -- EditMacro return values have varied historically. Re-read the protected
  -- resource and verify body + icon instead of trusting the return value.
  local currentName, currentIcon, currentBody = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
  if currentName == nil then return nil, currentIcon or "macro-info-read-failed:missing" end
  if type(currentName) ~= "string" then return nil, "edit-macro-verification-name-unavailable" end
  if tostring(currentName):lower() ~= tostring(expectedName or ""):lower() then
    return nil, "edit-macro-verification-name-mismatch"
  end
  if currentBody ~= body or not self:ManagedMacroIconMatches(currentIcon) then
    return nil, "edit-macro-verification-failed"
  end
  return tonumber(index) or index
end

function Manager:EnumerateMacroName(name)
  local normalizedName = tostring(name or ""):lower()

  -- GetMacroIndexByName returns only one duplicate. Enumerate both macro spaces
  -- when possible so a same-name personal macro can never be silently hidden.
  if type(GetNumMacros) == "function" and type(GetMacroInfo) == "function" then
    local accountLimit = accountMacroLimit()
    if not accountLimit then return nil, nil, "macro-account-boundary-unavailable" end
    local accountCount, characterCount, countError = readMacroCounts(accountLimit)
    if accountCount == nil then return nil, nil, countError end
    local matches = {}
    for index = 1, accountCount do
      local macroName, infoError = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
      if macroName == nil and infoError then return nil, nil, infoError end
      if type(macroName) == "string" and macroName:lower() == normalizedName then matches[#matches + 1] = index end
    end
    for index = accountLimit + 1, accountLimit + characterCount do
      local macroName, infoError = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
      if macroName == nil and infoError then return nil, nil, infoError end
      if type(macroName) == "string" and macroName:lower() == normalizedName then matches[#matches + 1] = index end
    end
    return matches, accountCount, nil
  end

  -- Name-only lookup is not sufficient ownership proof because duplicate macro
  -- names may exist in account and character spaces. Supported Midnight clients
  -- expose full enumeration; if that enumeration is unavailable, fail closed
  -- rather than risking an edit/create/delete against a hidden personal macro.
  return nil, nil, "macro-enumeration-unavailable"
end

function Manager:IsRouteMacroName(name)
  return type(name) == "string" and name:match(ROUTE_MACRO_PATTERN) ~= nil
end

function Manager:EnumerateAllMacros()
  if type(GetNumMacros) ~= "function" or type(GetMacroInfo) ~= "function" then
    return nil, "macro-enumeration-unavailable"
  end
  local accountLimit = accountMacroLimit()
  if not accountLimit then return nil, "macro-account-boundary-unavailable" end
  local accountCount, characterCount, countError = readMacroCounts(accountLimit)
  if accountCount == nil then return nil, countError end
  local entries = {}
  local function append(index)
    local name, icon, body = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
    if name == nil then
      -- Sparse slots are valid in mocked/client macro spaces; only propagate a
      -- real read error, not a missing slot.
      if type(icon) == "string" and icon:find("macro%-info%-read%-failed") then return nil, icon end
      return true
    end
    entries[#entries + 1] = { index = index, name = name, icon = icon, body = body }
    return true
  end
  for index = 1, accountCount do
    local ok, err = append(index)
    if not ok then return nil, err end
  end
  for index = accountLimit + 1, accountLimit + characterCount do
    local ok, err = append(index)
    if not ok then return nil, err end
  end
  return entries
end

function Manager:MacroLocation(index)
  index = tonumber(index)
  local accountLimit = accountMacroLimit()
  if not index or index <= 0 or not accountLimit then return nil end
  return index <= accountLimit and "account" or "character"
end

function Manager:ChoosePreferredMacroIndex(matches)
  if type(matches) ~= "table" or #matches == 0 then return 0 end
  local accountLimit = accountMacroLimit()
  if not accountLimit then return 0 end
  for _, index in ipairs(matches) do
    index = tonumber(index)
    if index and index > 0 and index <= accountLimit then return index end
  end
  return tonumber(matches[1]) or 0
end

function Manager:GetSmartMacroIndex(macroName)
  local matches, _, enumerateError = self:EnumerateMacroName(macroName)
  if not matches then return nil, enumerateError or "macro-enumeration-failed" end
  return self:ChoosePreferredMacroIndex(matches)
end

function Manager:CreateSmartMacro(macroName, body)
  -- Recheck directly before creation to close the same-name race.
  local existing, existingError = self:GetSmartMacroIndex(macroName)
  if existing == nil then return nil, existingError end
  if existing > 0 then return existing, "existing" end

  local accountLimit = accountMacroLimit()
  if not accountLimit then return nil, "macro-account-boundary-unavailable" end
  local accountCount, _, countError = readMacroCounts(accountLimit)
  if accountCount == nil then return nil, countError end
  local failures = {}
  local function tryCreate(perCharacter, location)
    local created, createError = protectedMacroCall(CreateMacro, macroName, self:GetSmartMacroIcon(), body, perCharacter)
    if created then return created, location end
    local racedIndex = self:GetSmartMacroIndex(macroName)
    if racedIndex and racedIndex > 0 then return racedIndex, "existing-after-create-race" end
    failures[#failures + 1] = location..":"..tostring(createError)
  end

  -- Prefer account-wide storage when its count is readable and below the known
  -- account boundary. If unavailable/full, attempt character storage directly.
  -- Do not hard-code a character capacity: CreateMacro is the authority and a
  -- failed protected call is handled below.
  if accountCount < accountLimit then
    local created, location = tryCreate(false, "account")
    if created then return created, location end
  end
  local created, location = tryCreate(true, "character")
  if created then return created, location end
  return nil, #failures > 0 and table.concat(failures, "|") or "macro-slots-insufficient"
end

function Manager:RetireManagedMacros(managed, macroName)
  if type(DeleteMacro) ~= "function" then return false, "delete-macro-unavailable" end
  local indexes = {}
  for _, entry in ipairs(managed or {}) do
    local index = tonumber(entry.index)
    if index and index > 0 then indexes[#indexes + 1] = index end
  end
  table.sort(indexes, function(left, right) return left > right end)

  for _, index in ipairs(indexes) do
    local ok, deleteError = pcall(DeleteMacro, index)
    if not ok then return false, "delete-macro-failed:"..tostring(deleteError) end
  end

  -- Deleting a macro can shift later indices. Verify by reserved name after all
  -- deletes rather than trusting DeleteMacro's return value or stale indices.
  local remaining, _, enumerateError = self:EnumerateMacroName(macroName)
  if not remaining then return false, enumerateError or "macro-enumeration-failed-after-delete" end
  if #remaining > 0 then return false, "managed-macro-retirement-unverified:"..tostring(macroName) end

  self.log("WARN", tostring(macroName or "Managed macro").." was removed after a failed safety refresh so an outdated target macro cannot remain active.", false)
  return true
end

function Manager:RetireRecognizedReservedMacros(reason)
  if type(DeleteMacro) ~= "function" then return false, "delete-macro-unavailable" end

  -- Fail closed across the whole reserved pair. A refresh error on MDTPM2 must
  -- never leave an older MDTPM1 body executable (or vice versa). Only resources
  -- whose exact reserved name, recognized body and dedicated icon prove addon
  -- ownership are eligible; personal same-name macros are deliberately skipped.
  local managedByIndex = {}
  for _, macroName in ipairs(self.macroNames) do
    local matches, _, enumerateError = self:EnumerateMacroName(macroName)
    if not matches then return false, enumerateError or "macro-enumeration-failed-during-pair-retirement" end
    for _, rawIndex in ipairs(matches) do
      local index = tonumber(rawIndex)
      if index and index > 0 then
        local currentName, currentIcon, currentBody = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
        if currentName == nil then return false, currentIcon or "macro-info-read-failed-during-pair-retirement" end
        if type(currentName) == "string" and currentName:lower() == tostring(macroName):lower()
          and self:IsRecognizedManagedBody(currentBody, currentIcon) then
          managedByIndex[index] = true
        end
      end
    end
  end

  local indexes = {}
  for index in pairs(managedByIndex) do indexes[#indexes + 1] = index end
  table.sort(indexes, function(left, right) return left > right end)
  for _, index in ipairs(indexes) do
    local ok, deleteError = pcall(DeleteMacro, index)
    if not ok then return false, "delete-macro-failed:"..tostring(deleteError) end
  end

  -- Verify ownership, not mere name absence: a personal collision is allowed to
  -- remain, but no recognized addon-managed reserved macro may survive cleanup.
  for _, macroName in ipairs(self.macroNames) do
    local matches, _, enumerateError = self:EnumerateMacroName(macroName)
    if not matches then return false, enumerateError or "macro-enumeration-failed-after-pair-retirement" end
    for _, rawIndex in ipairs(matches) do
      local index = tonumber(rawIndex)
      if index and index > 0 then
        local currentName, currentIcon, currentBody = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
        if currentName == nil then return false, currentIcon or "macro-info-read-failed-after-pair-retirement" end
        if type(currentName) == "string" and currentName:lower() == tostring(macroName):lower()
          and self:IsRecognizedManagedBody(currentBody, currentIcon) then
          return false, "managed-pair-retirement-unverified:"..tostring(macroName)..":"..tostring(index)
        end
      end
    end
  end

  if #indexes > 0 then
    self.log("WARN", "Managed marker macros were retired after a pair-level safety failure: "..tostring(reason or "unknown"), false)
  end
  return true
end

function Manager:ParkRecognizedRouteMacros(reason, keepNames)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    self.pendingRefresh = true
    return false, "in-combat"
  end
  if type(EditMacro) ~= "function" then return false, "edit-macro-unavailable" end
  keepNames = type(keepNames) == "table" and keepNames or {}
  local entries, enumerateError = self:EnumerateAllMacros()
  if not entries then return false, enumerateError end

  local parkedIndexes = {}
  for _, entry in ipairs(entries) do
    local normalized = type(entry.name) == "string" and entry.name:lower() or ""
    if self:IsRouteMacroName(entry.name) and not keepNames[normalized]
      and self:IsRecognizedManagedBody(entry.body, entry.icon) then
      if entry.body ~= MarkerMacro.SAFE_IDLE_MACRO or not self:ManagedMacroIconMatches(entry.icon) then
        local edited, editError = self:EditManagedMacro(entry.index, MarkerMacro.SAFE_IDLE_MACRO, entry.name)
        if not edited then return false, "park-route-macro-failed:"..tostring(entry.name)..":"..tostring(editError) end
      end
      parkedIndexes[#parkedIndexes + 1] = tonumber(entry.index)
    end
  end

  -- Verify that every managed route macro outside the keep-set is inert. A
  -- personal MPM### macro is intentionally ignored because ownership is not
  -- proven by its name alone.
  local remaining, verifyError = self:EnumerateAllMacros()
  if not remaining then return false, verifyError end
  for _, entry in ipairs(remaining) do
    local normalized = type(entry.name) == "string" and entry.name:lower() or ""
    if self:IsRouteMacroName(entry.name) and not keepNames[normalized]
      and self:IsRecognizedManagedBody(entry.body, entry.icon)
      and entry.body ~= MarkerMacro.SAFE_IDLE_MACRO then
      return false, "managed-route-macro-parking-unverified:"..tostring(entry.name)..":"..tostring(entry.index)
    end
  end
  if #parkedIndexes > 0 then
    self.log("INFO", "Managed route macros were parked safely: "..tostring(reason or "route-refresh"), false)
  end
  return true, #parkedIndexes
end

function Manager:FailCloseRouteMacros(reason)
  local parked, parkResult = self:ParkRecognizedRouteMacros(reason or "route-fail-close")
  if parked then return true, "parked", parkResult end

  -- Parking is preferred because it preserves action-bar references. Deletion is
  -- only the emergency fallback when an active managed body cannot be made inert.
  local retired, retireError = self:RetireRecognizedRouteMacros((reason or "route-fail-close")..":park-failed")
  if retired then return true, "retired-after-park-failed", retireError end
  return false, nil, tostring(parkResult)..":"..tostring(retireError)
end

function Manager:RetireRecognizedRouteMacros(reason, keepNames)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    self.pendingRefresh = true
    return false, "in-combat"
  end
  if type(DeleteMacro) ~= "function" then return false, "delete-macro-unavailable" end
  keepNames = type(keepNames) == "table" and keepNames or {}
  local entries, enumerateError = self:EnumerateAllMacros()
  if not entries then return false, enumerateError end
  local indexes = {}
  for _, entry in ipairs(entries) do
    local normalized = type(entry.name) == "string" and entry.name:lower() or ""
    if self:IsRouteMacroName(entry.name) and not keepNames[normalized]
      and self:IsRecognizedManagedBody(entry.body, entry.icon) then
      indexes[#indexes + 1] = tonumber(entry.index)
    end
  end
  table.sort(indexes, function(left, right) return left > right end)
  for _, index in ipairs(indexes) do
    local ok, deleteError = pcall(DeleteMacro, index)
    if not ok then return false, "delete-route-macro-failed:"..tostring(deleteError) end
  end

  local remaining, verifyError = self:EnumerateAllMacros()
  if not remaining then return false, verifyError end
  for _, entry in ipairs(remaining) do
    local normalized = type(entry.name) == "string" and entry.name:lower() or ""
    if self:IsRouteMacroName(entry.name) and not keepNames[normalized]
      and self:IsRecognizedManagedBody(entry.body, entry.icon) then
      return false, "managed-route-macro-retirement-unverified:"..tostring(entry.name)..":"..tostring(entry.index)
    end
  end
  if #indexes > 0 then
    self.log("WARN", "Managed route macros were retired: "..tostring(reason or "route-refresh"), false)
  end
  return true, #indexes
end

function Manager:GetNamedBodyStatus(macroName, desiredBody)
  local matches, _, enumerateError = self:EnumerateMacroName(macroName)
  if not matches then return nil, enumerateError or "macro-enumeration-failed" end
  local preferred = self:ChoosePreferredMacroIndex(matches)
  local exists = preferred and preferred > 0 or false
  local conflictIndex
  local allCurrent = exists
  local allRecognized = exists
  for _, rawIndex in ipairs(matches) do
    local index = tonumber(rawIndex)
    if index and index > 0 then
      local currentName, currentIcon, currentBody = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
      if currentName == nil then return nil, currentIcon or "macro-info-read-failed" end
      if not self:IsRecognizedManagedBody(currentBody, currentIcon) then
        allRecognized = false
        conflictIndex = conflictIndex or index
      end
      if currentBody ~= desiredBody or not self:ManagedMacroIconMatches(currentIcon) then allCurrent = false end
    end
  end
  return {
    name = macroName,
    index = exists and preferred or nil,
    exists = exists,
    current = allCurrent == true,
    recognized = allRecognized == true,
    managed = allRecognized == true,
    conflict = conflictIndex ~= nil,
    conflictIndex = conflictIndex,
    duplicateCount = math.max(0, #matches - 1),
    location = exists and self:MacroLocation(preferred) or nil,
    body = desiredBody,
    error = conflictIndex and ("reserved-macro-name-conflict:"..tostring(macroName)..":"..tostring(conflictIndex)) or nil,
  }
end

function Manager:RefreshDescriptorSet(descriptors, reason, pickupName, createIfMissing)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    self.pendingRefresh = true
    return nil, "in-combat"
  end
  self.pendingRefresh = false
  if type(CreateMacro) ~= "function" or type(EditMacro) ~= "function" or type(GetMacroInfo) ~= "function" then
    return nil, "macro-api-unavailable"
  end
  descriptors = type(descriptors) == "table" and descriptors or {}
  local desiredByName, ordered = {}, {}
  for _, descriptor in ipairs(descriptors) do
    local name = type(descriptor) == "table" and descriptor.name or nil
    local body = type(descriptor) == "table" and descriptor.body or nil
    if not self:IsRouteMacroName(name) then return nil, "route-macro-name-invalid:"..tostring(name) end
    if type(body) ~= "string" or body == "" or not MarkerMacro.IsRecognizedBody(body) then
      return nil, "route-macro-body-invalid:"..tostring(name)
    end
    local normalized = name:lower()
    if desiredByName[normalized] then return nil, "route-macro-name-duplicate:"..tostring(name) end
    desiredByName[normalized] = descriptor
    ordered[#ordered + 1] = descriptor
  end
  table.sort(ordered, function(left, right) return tostring(left.name) < tostring(right.name) end)

  -- Discover every desired-name collision before mutating anything. A personal
  -- MPM###A/B macro is never edited or deleted.
  for _, descriptor in ipairs(ordered) do
    local matches, _, enumerateError = self:EnumerateMacroName(descriptor.name)
    if not matches then return nil, enumerateError or "macro-enumeration-failed" end
    if #matches > 0 then
      local managed, preflightError = self:PreflightNamedMacro(descriptor.name, matches)
      if not managed then
        local closed, _, closeError = self:FailCloseRouteMacros("preflight:"..tostring(preflightError))
        if closed then return nil, preflightError end
        return nil, tostring(preflightError)..":"..tostring(closeError)
      end
    end
  end

  local results = {}
  for _, descriptor in ipairs(ordered) do
    local matches, _, enumerateError = self:EnumerateMacroName(descriptor.name)
    if not matches then
      self:FailCloseRouteMacros("enumeration-failed")
      return nil, enumerateError or "macro-enumeration-failed"
    end
    if #matches == 0 then
      if createIfMissing ~= true then
        results[#results + 1] = { name = descriptor.name, missing = true, descriptor = descriptor }
      else
        local created, locationOrError = self:CreateSmartMacro(descriptor.name, descriptor.body)
        if not created then
          local closed, _, closeError = self:FailCloseRouteMacros("create:"..tostring(descriptor.name))
          local baseError = "route-macro-create-failed:"..tostring(descriptor.name)..":"..tostring(locationOrError)
          if closed then return nil, baseError end
          return nil, baseError..":"..tostring(closeError)
        end
        matches = { tonumber(created) }
        self.log("INFO", tostring(descriptor.name).." created/resolved in "..tostring(locationOrError).." macro space.", false)
      end
    end

    if #matches > 0 then
      local managed, preflightError = self:PreflightNamedMacro(descriptor.name, matches)
      if not managed then
        local closed, _, closeError = self:FailCloseRouteMacros("post-create-preflight:"..tostring(preflightError))
        if closed then return nil, preflightError end
        return nil, tostring(preflightError)..":"..tostring(closeError)
      end
      local preferred = self:ChoosePreferredMacroIndex(matches)
      for _, entry in ipairs(managed) do
        if entry.body ~= descriptor.body or not self:ManagedMacroIconMatches(entry.icon) then
          local edited, editError = self:EditManagedMacro(entry.index, descriptor.body, descriptor.name)
          if not edited then
            local closed, _, closeError = self:FailCloseRouteMacros("edit:"..tostring(descriptor.name))
            local baseError = "route-macro-edit-failed:"..tostring(descriptor.name)..":"..tostring(editError)
            if closed then return nil, baseError end
            return nil, baseError..":"..tostring(closeError)
          end
        end
      end
      results[#results + 1] = {
        name = descriptor.name,
        index = preferred,
        location = self:MacroLocation(preferred),
        descriptor = descriptor,
      }
    end
  end

  -- A route edit can reduce its pull/macro count. Keep old managed macro slots
  -- inert instead of deleting them so existing action-bar references survive a
  -- dungeon/route switch. Unrelated similarly named personal macros remain.
  local keepNames = {}
  for name in pairs(desiredByName) do keepNames[name] = true end
  local staleOK, staleError = self:ParkRecognizedRouteMacros("stale-route-macros", keepNames)
  if not staleOK then
    local closed = self:FailCloseRouteMacros("stale-parking-failed")
    if not closed then return nil, staleError end
    return nil, staleError
  end

  -- Verify exactly what will be shipped to the action bars, rather than trusting
  -- EditMacro/CreateMacro return values.
  for _, result in ipairs(results) do
    if result.index then
      local status, statusError = self:GetNamedBodyStatus(result.name, result.descriptor.body)
      if not status or not status.current or status.conflict then
        self:FailCloseRouteMacros("route-macro-verification-failed")
        return nil, statusError or (status and status.error) or ("route-macro-verification-failed:"..tostring(result.name))
      end
    end
  end

  if pickupName and type(PickupMacro) == "function" then
    for _, result in ipairs(results) do
      if result.name == pickupName and result.index then
        local ok, pickupError = pcall(PickupMacro, result.index)
        if not ok then return nil, "route-macro-pickup-failed:"..tostring(pickupError) end
        break
      end
    end
  end
  return results
end

function Manager:GetDescriptorSetStatus(descriptors)
  descriptors = type(descriptors) == "table" and descriptors or {}
  local statuses, currentCount, conflictCount, missingCount = {}, 0, 0, 0
  local desiredNames = {}
  for _, descriptor in ipairs(descriptors) do
    if type(descriptor) == "table" and self:IsRouteMacroName(descriptor.name) then
      desiredNames[descriptor.name:lower()] = true
      local status, statusError = self:GetNamedBodyStatus(descriptor.name, descriptor.body)
      if not status then
        status = { name = descriptor.name, exists = false, current = false, error = statusError }
      end
      statuses[#statuses + 1] = status
      if status.current then currentCount = currentCount + 1 end
      if status.conflict then conflictCount = conflictCount + 1 end
      if not status.exists then missingCount = missingCount + 1 end
    end
  end
  local staleCount, parkedCount, staleActiveCount = 0, 0, 0
  local allEntries = self:EnumerateAllMacros()
  if allEntries then
    for _, entry in ipairs(allEntries) do
      local normalized = type(entry.name) == "string" and entry.name:lower() or ""
      if self:IsRouteMacroName(entry.name) and not desiredNames[normalized]
        and self:IsRecognizedManagedBody(entry.body, entry.icon) then
        staleCount = staleCount + 1
        if entry.body == MarkerMacro.SAFE_IDLE_MACRO or entry.body == LEGACY_SAFE_IDLE_MACRO then
          parkedCount = parkedCount + 1
        else
          staleActiveCount = staleActiveCount + 1
        end
      end
    end
  end
  return {
    desiredCount = #statuses,
    currentCount = currentCount,
    missingCount = missingCount,
    conflictCount = conflictCount,
    staleCount = staleCount,
    parkedCount = parkedCount,
    staleActiveCount = staleActiveCount,
    current = currentCount == #statuses and conflictCount == 0 and staleActiveCount == 0,
    macros = statuses,
  }
end

function Manager:PreflightNamedMacro(macroName, matches)
  local managed = {}
  for _, rawIndex in ipairs(matches or {}) do
    local index = tonumber(rawIndex)
    if index and index > 0 then
      local currentName, currentIcon, currentBody = safeMacroRead(GetMacroInfo, "macro-info-read-failed", index)
      if currentName == nil then return nil, currentIcon or "macro-info-read-failed:missing" end
      if type(currentName) ~= "string" or currentName:lower() ~= tostring(macroName):lower() then
        return nil, "managed-macro-name-mismatch:"..tostring(macroName)..":"..tostring(index)
      end
      if not self:IsRecognizedManagedBody(currentBody, currentIcon) then
        return nil, "reserved-macro-name-conflict:"..tostring(macroName)..":"..tostring(index)
      end
      managed[#managed + 1] = { index = index, icon = currentIcon, body = currentBody }
    end
  end
  return managed
end

function Manager:RefreshNamed(macroName, batchIndex, reason, createIfMissing)
  local body, bodyWarning = self.desiredBody(batchIndex)
  if not body then return nil, bodyWarning end

  local matches, _, enumerateError = self:EnumerateMacroName(macroName)
  if not matches then return nil, enumerateError or "macro-enumeration-failed", bodyWarning end
  if #matches == 0 then
    if not createIfMissing then return false, "macro-missing:"..tostring(macroName), bodyWarning end
    local created, locationOrError = self:CreateSmartMacro(macroName, body)
    if not created then return nil, "smart-macro-create-failed:"..tostring(macroName)..":"..tostring(locationOrError), bodyWarning end
    matches = { tonumber(created) }
    self.log("INFO", tostring(macroName).." created/resolved in "..tostring(locationOrError).." macro space.", false)
  end

  -- Preflight all duplicates before changing any resource. This keeps refresh
  -- transactional when a managed and personal same-name macro coexist.
  local managed, preflightError = self:PreflightNamedMacro(macroName, matches)
  if not managed then return nil, preflightError, bodyWarning end

  local preferred = self:ChoosePreferredMacroIndex(matches)
  for _, entry in ipairs(managed) do
    if entry.body ~= body or not self:ManagedMacroIconMatches(entry.icon) then
      local edited, editError = self:EditManagedMacro(entry.index, body, macroName)
      if not edited then
        local retired, retireError = self:RetireManagedMacros(managed, macroName)
        if retired then return nil, "smart-macro-edit-failed-retired:"..tostring(macroName)..":"..tostring(editError), bodyWarning end
        return nil, "smart-macro-edit-failed:"..tostring(macroName)..":"..tostring(editError)..":"..tostring(retireError), bodyWarning
      end
    end
  end

  self.log("DEBUG", tostring(macroName).." refreshed: "..tostring(reason or "unspecified"), false)
  return preferred, nil, bodyWarning
end

function Manager:RefreshAll(reason, pickupIndex, createIfMissing)
  createIfMissing = createIfMissing == true and self.dungeonSessionActive()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    self.pendingRefresh = true
    return nil, "in-combat"
  end
  self.pendingRefresh = false
  if type(CreateMacro) ~= "function" or type(EditMacro) ~= "function" or type(GetMacroInfo) ~= "function" then
    return nil, "macro-api-unavailable"
  end

  -- Treat the two reserved names as one transaction. Discover every existing
  -- collision before editing or creating either macro, so MDTPM1 cannot be
  -- partially refreshed when MDTPM2 is an unrelated personal macro (or vice versa).
  for _, macroName in ipairs(self.macroNames) do
    local matches, _, enumerateError = self:EnumerateMacroName(macroName)
    if not matches then return nil, enumerateError or "macro-enumeration-failed" end
    if #matches > 0 then
      local managed, preflightError = self:PreflightNamedMacro(macroName, matches)
      if not managed then
        local retired, retireError = self:RetireRecognizedReservedMacros("preflight:"..tostring(preflightError))
        if retired then return nil, preflightError end
        return nil, tostring(preflightError)..":"..tostring(retireError)
      end
    end
  end

  local results = {}
  for batchIndex, macroName in ipairs(self.macroNames) do
    local index, operationError, warning = self:RefreshNamed(macroName, batchIndex, reason, createIfMissing)
    if index == nil then
      local pairError = operationError or ("macro-refresh-failed:"..tostring(macroName))
      local retired, retireError = self:RetireRecognizedReservedMacros("refresh:"..tostring(pairError))
      if retired then return nil, pairError end
      return nil, tostring(pairError)..":"..tostring(retireError)
    end
    results[batchIndex] = {
      name = macroName,
      index = index or nil,
      missing = index == false,
      warning = warning,
    }
  end

  pickupIndex = tonumber(pickupIndex)
  if pickupIndex and results[pickupIndex] and results[pickupIndex].index and type(PickupMacro) == "function" then
    local ok, pickupError = pcall(PickupMacro, results[pickupIndex].index)
    if not ok then return nil, "smart-macro-pickup-failed:"..tostring(pickupError) end
  end
  return results
end

function Manager:RefreshPrimary(reason, pickup, createIfMissing)
  local results, refreshError = self:RefreshAll(reason, pickup and 1 or nil, createIfMissing)
  if not results then return nil, refreshError end
  return results[1].index, results[1].warning
end

function Manager:GetStatus(batchIndex)
  batchIndex = tonumber(batchIndex) or 1
  local macroName = self.macroNames[batchIndex]
  local desiredBody, bodyWarning = self.desiredBody(batchIndex)
  local matches, _, enumerateError = self:EnumerateMacroName(macroName)
  local index = matches and self:ChoosePreferredMacroIndex(matches) or nil
  local exists = type(index) == "number" and index > 0
  local currentBody, currentIcon, readError, conflictIndex
  local allCurrent = exists
  local allRecognized = exists

  if matches and type(GetMacroInfo) == "function" then
    for _, macroIndex in ipairs(matches) do
      local _, second, macroBody = safeMacroRead(GetMacroInfo, "macro-info-read-failed", macroIndex)
      if macroBody == nil and type(second) == "string" and second:find("macro%-info%-read%-failed") then
        readError = second
        allCurrent = false
        allRecognized = false
        break
      end
      if tonumber(macroIndex) == tonumber(index) then
        currentIcon = second
        currentBody = macroBody
      end
      if macroBody ~= desiredBody or not self:ManagedMacroIconMatches(second) then allCurrent = false end
      if not self:IsRecognizedManagedBody(macroBody, second) then
        allRecognized = false
        conflictIndex = conflictIndex or tonumber(macroIndex)
      end
    end
  end

  local conflict = conflictIndex ~= nil
  local statusError = enumerateError or readError
  if not statusError and conflict then
    statusError = "reserved-macro-name-conflict:"..tostring(macroName)..":"..tostring(conflictIndex)
  end

  local boundKey = "not assigned"
  local bindingError
  if type(GetBindingKey) == "function" then
    local ok, key1, key2 = pcall(GetBindingKey, "CLICK "..self.buttonName..":LeftButton")
    if not ok then
      bindingError = "binding-read-failed:"..tostring(key1)
    elseif isSecret(key1) or isSecret(key2) then
      bindingError = "binding-read-secret"
    else
      boundKey = key1 and key2 and (key1..", "..key2) or key1 or key2 or boundKey
    end
  else
    bindingError = "binding-api-unavailable"
  end

  return {
    name = macroName,
    index = exists and index or nil,
    exists = exists,
    current = allCurrent == true,
    recognized = allRecognized == true,
    managed = allRecognized == true,
    conflict = conflict,
    conflictIndex = conflictIndex,
    location = exists and self:MacroLocation(index) or nil,
    takeoverRequired = conflict,
    duplicateCount = matches and math.max(0, #matches - 1) or 0,
    error = statusError,
    warning = bodyWarning,
    body = desiredBody,
    phase = "direct",
    boundKey = boundKey,
    bindingError = bindingError,
  }
end
