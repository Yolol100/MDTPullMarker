local addonName, Addon = ...

local PREFIX = "|cff33ff99MDT Pull Marker:|r "
local ADDON_VERSION = "1.0.0-rc54"
local MAX_LOG_ENTRIES = 100

Addon.Name = addonName
Addon.Version = ADDON_VERSION
Addon.Constants = {
  SmartButtonName = "MDTPullMarkerSmartButton",
  SmartMacroName = "MDTPM1",
  SmartMacroName2 = "MDTPM2",
  LegacySmartMacroName = "MDTPM",
  AutomaticTargetingWarning = "|cffffad33A marked mob name is ambiguous in the bound route or known dungeon metadata: WoW cannot safely address the intended physical clone automatically. This pull is parked instead of risking a wrong marker.|r",
  MarkerNames = {
    [1] = "Star",
    [2] = "Circle",
    [3] = "Diamond",
    [4] = "Triangle",
    [5] = "Moon",
    [6] = "Square",
    [7] = "Cross",
    [8] = "Skull",
  },
}

_G.BINDING_HEADER_MDTPULLMARKER = "MDT Pull Marker"
_G["BINDING_NAME_CLICK "..Addon.Constants.SmartButtonName..":LeftButton"] = "MDT route marker: mark up to 3 targets"

local function isSecret(value)
  return type(issecretvalue) == "function" and issecretvalue(value)
end

local function safeDisplayString(value)
  if isSecret(value) then return "<secret>" end
  return tostring(value or "")
end

local function chat(message)
  print(PREFIX..safeDisplayString(message))
end

local function timestamp()
  if type(date) == "function" then return date("%Y-%m-%d %H:%M:%S") end
  return "unknown-time"
end

local function getDatabase()
  if Addon.Database and type(Addon.Database.Get) == "function" then return Addon.Database.Get() end
end

local function getGlobal()
  local database = getDatabase()
  return database and database.global or nil
end

local function trimLogs(global)
  if not global or type(global.logs) ~= "table" then return end
  while #global.logs > MAX_LOG_ENTRIES do table.remove(global.logs, 1) end
end

local function log(level, message, showInChat)
  level = safeDisplayString(level or "INFO")
  message = safeDisplayString(message)
  local global = getGlobal()
  if global then
    global.logs = type(global.logs) == "table" and global.logs or {}
    global.logs[#global.logs + 1] = {
      time = timestamp(),
      level = level,
      message = message,
    }
    trimLogs(global)
  end
  if showInChat or (global and global.debug) then
    chat(message)
  end
end

Addon.Chat = chat
Addon.Log = log
Addon.IsSecret = isSecret
Addon.GetDatabase = getDatabase
Addon.GetGlobal = getGlobal