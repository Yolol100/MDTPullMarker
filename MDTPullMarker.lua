local addonName, Addon = ...

local PREFIX = "|cff33ff99MDT Pull Marker:|r "
local ADDON_VERSION = "1.0.0-rc58"
local MAX_LOG_ENTRIES = 100
local MAX_LOG_LEVEL_BYTES = 16
local MAX_LOG_MESSAGE_BYTES = 800

Addon.Name = addonName
Addon.Version = ADDON_VERSION
Addon.L = Addon.L or setmetatable({}, { __index = function(_, key) return key end })
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

local function isSecret(value)
  return type(issecretvalue) == "function" and issecretvalue(value)
end

local function safeDisplayString(value)
  if isSecret(value) then return "<secret>" end
  return tostring(value or "")
end

local function utf8SafePrefix(value, maximum)
  if #value <= maximum then return value end
  local start = maximum
  while start > 1 do
    local byte = value:byte(start)
    if not byte or byte < 0x80 or byte >= 0xC0 then break end
    start = start - 1
  end
  local lead = value:byte(start) or 0
  local expected = 1
  if lead >= 0xC2 and lead <= 0xDF then expected = 2
  elseif lead >= 0xE0 and lead <= 0xEF then expected = 3
  elseif lead >= 0xF0 and lead <= 0xF4 then expected = 4 end
  local cut = (start + expected - 1 <= maximum) and maximum or (start - 1)
  return cut > 0 and value:sub(1, cut) or ""
end

local function boundedLogString(value, maximum)
  local text = safeDisplayString(value)
  if #text > maximum then text = utf8SafePrefix(text, maximum) end
  return text
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
  level = boundedLogString(level or "INFO", MAX_LOG_LEVEL_BYTES)
  message = boundedLogString(message, MAX_LOG_MESSAGE_BYTES)
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
