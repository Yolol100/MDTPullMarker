local _, Addon = ...

local Resolver = {}
Addon.CreatureNameResolver = Resolver

local DataUtils = Addon.DataUtils
local MAX_CACHE_ENTRIES = 4096
local cache = {}
local cacheOrder = {}
local cacheCount = 0
local nextEvictionSlot = 1

local function isSecret(value)
  return Addon.IsSecret and Addon.IsSecret(value) or false
end

local function clientLocale()
  if type(GetLocale) ~= "function" then return "unknown" end
  local ok, value = pcall(GetLocale)
  if not ok or isSecret(value) or type(value) ~= "string" then return "unknown" end
  return value
end

local function sanitize(value)
  if isSecret(value) or type(value) ~= "string" then return nil end
  local ok, cleaned = pcall(function()
    local text = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = DataUtils and DataUtils.Trim and DataUtils.Trim(text) or text:match("^%s*(.-)%s*$")
    if not text or text == "" or text == "Unknown" or #text > 120 or text:find("[%c%[%];]") then return nil end
    return text
  end)
  return ok and cleaned or nil
end

local function tooltipName(npcID)
  npcID = DataUtils and DataUtils.PositiveInteger and DataUtils.PositiveInteger(npcID) or tonumber(npcID)
  if not npcID or type(C_TooltipInfo) ~= "table" or type(C_TooltipInfo.GetHyperlink) ~= "function" then
    return nil, "tooltip-api-unavailable"
  end
  local hyperlink = "unit:Creature-0-0-0-0-"..tostring(npcID)
  local ok, tooltipData = pcall(C_TooltipInfo.GetHyperlink, hyperlink)
  if not ok or isSecret(tooltipData) or type(tooltipData) ~= "table" then return nil, "tooltip-name-unavailable" end
  local lines = tooltipData.lines
  if isSecret(lines) or type(lines) ~= "table" then return nil, "tooltip-name-unavailable" end
  local first = lines[1]
  if isSecret(first) or type(first) ~= "table" then return nil, "tooltip-name-unavailable" end
  local name = sanitize(first.leftText)
  if not name then return nil, "tooltip-name-unavailable" end
  return name, "localized-tooltip"
end

local function remember(key, value)
  if not key then return end
  if cache[key] ~= nil then
    cache[key] = value
    return
  end

  if cacheCount < MAX_CACHE_ENTRIES then
    cacheCount = cacheCount + 1
    cacheOrder[cacheCount] = key
  else
    local evictedKey = cacheOrder[nextEvictionSlot]
    if evictedKey ~= nil then cache[evictedKey] = nil end
    cacheOrder[nextEvictionSlot] = key
    nextEvictionSlot = nextEvictionSlot + 1
    if nextEvictionSlot > MAX_CACHE_ENTRIES then nextEvictionSlot = 1 end
  end
  cache[key] = value
end

function Resolver:Resolve(npcID, fallbackName)
  local locale = clientLocale()
  local fallback = sanitize(fallbackName)
  if (locale == "enUS" or locale == "enGB") and fallback then
    return fallback, "source-client-locale", true
  end

  npcID = DataUtils and DataUtils.PositiveInteger and DataUtils.PositiveInteger(npcID) or tonumber(npcID)
  local key = npcID and (locale..":"..tostring(npcID)) or nil
  local cached = key and cache[key] or nil
  if cached then return cached.name, cached.status, cached.verified end

  local resolved, status = tooltipName(npcID)
  if resolved then
    remember(key, { name = resolved, status = status, verified = true })
    return resolved, status, true
  end

  if fallback then return fallback, "fallback-unverified", false end
  return nil, status or "target-name-unavailable", false
end

function Resolver:Clear()
  cache = {}
  cacheOrder = {}
  cacheCount = 0
  nextEvictionSlot = 1
end

function Resolver:GetState()
  return { locale = clientLocale(), cachedNames = cacheCount }
end
