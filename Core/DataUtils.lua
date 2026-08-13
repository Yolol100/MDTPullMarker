local _, Addon = ...

local DataUtils = {}
Addon.DataUtils = DataUtils

local DEFAULT_MAX_DEPTH = 12
local DEFAULT_MAX_ENTRIES = 20000

local HASH_MODULO_32 = 4294967296

function DataUtils.StableHash(value)
  if DataUtils.IsSecret(value) then return nil end
  local text = tostring(value or "")
  local hashA = 5381
  local hashB = 0
  for index = 1, #text do
    local byte = text:byte(index)
    hashA = (hashA * 33 + byte) % HASH_MODULO_32
    hashB = (hashB * 65599 + byte) % HASH_MODULO_32
  end
  return ("%08x%08x"):format(hashA, hashB)
end

function DataUtils.IsSecret(value)
  return Addon.IsSecret and Addon.IsSecret(value) or false
end

function DataUtils.Trim(value)
  if type(value) ~= "string" then return nil end
  return value:match("^%s*(.-)%s*$")
end

local function utf8SequenceLength(byte)
  if not byte or byte < 0x80 then return 1 end
  if byte >= 0xC2 and byte <= 0xDF then return 2 end
  if byte >= 0xE0 and byte <= 0xEF then return 3 end
  if byte >= 0xF0 and byte <= 0xF4 then return 4 end
  return 1
end

function DataUtils.UTF8SafePrefix(value, maxBytes)
  if type(value) ~= "string" then return nil end
  maxBytes = math.floor(tonumber(maxBytes) or #value)
  if maxBytes <= 0 then return "" end
  if #value <= maxBytes then return value end

  local start = maxBytes
  while start > 1 do
    local byte = value:byte(start)
    if not byte or byte < 0x80 or byte >= 0xC0 then break end
    start = start - 1
  end
  local expected = utf8SequenceLength(value:byte(start))
  local cut = (start + expected - 1 <= maxBytes) and maxBytes or (start - 1)
  return cut > 0 and value:sub(1, cut) or ""
end

function DataUtils.SafeString(value, maxLength, allowEmpty)
  if DataUtils.IsSecret(value) or type(value) ~= "string" then return nil end
  value = DataUtils.Trim(value) or ""
  if not allowEmpty and value == "" then return nil end
  maxLength = tonumber(maxLength) or 1024
  if #value > maxLength then value = DataUtils.UTF8SafePrefix(value, maxLength) end
  return value
end

-- Identity/external values must never silently become a different value merely
-- because they exceed a local bound. Use this for persisted identifiers and
-- API identity fields; SafeString remains appropriate for display/log clipping.
function DataUtils.ValidatedString(value, maxLength, allowEmpty)
  if DataUtils.IsSecret(value) or type(value) ~= "string" then return nil end
  value = DataUtils.Trim(value) or ""
  if not allowEmpty and value == "" then return nil end
  maxLength = tonumber(maxLength) or 1024
  if #value > maxLength then return nil end
  return value
end


local NAME_PUNCTUATION_REPLACEMENTS = {
  ["\194\160"] = " ", -- non-breaking space
  ["‘"] = "'", ["’"] = "'", ["‚"] = "'", ["‛"] = "'",
  ["‐"] = "-", ["‑"] = "-", ["‒"] = "-", ["–"] = "-", ["—"] = "-", ["−"] = "-",
}

function DataUtils.NormalizeName(value)
  value = DataUtils.SafeString(value, 512, false)
  if not value then return nil end
  value = value:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  for source, replacement in pairs(NAME_PUNCTUATION_REPLACEMENTS) do
    value = value:gsub(source, replacement)
  end
  value = value:gsub("[%p%s]+", "")
  return value ~= "" and value or nil
end

function DataUtils.SafeNumber(value)
  if DataUtils.IsSecret(value) then return nil end
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
  return value
end

function DataUtils.PositiveInteger(value, maximum)
  local number = DataUtils.SafeNumber(value)
  if not number or number < 1 or number % 1 ~= 0 then return nil end
  if maximum and number > maximum then return nil end
  return number
end

local function deepCopyInternal(value, state, depth)
  if DataUtils.IsSecret(value) then return nil, "secret-value" end
  local valueType = type(value)
  if valueType == "nil" or valueType == "string" or valueType == "number" or valueType == "boolean" then
    return value
  end
  if valueType ~= "table" then return nil, "unsupported-type:"..valueType end
  if depth > state.maxDepth then return nil, "max-depth" end
  if state.seen[value] then return nil, "cycle" end

  state.seen[value] = true
  local result = {}
  for key, child in pairs(value) do
    state.entries = state.entries + 1
    if state.entries > state.maxEntries then
      state.seen[value] = nil
      return nil, "max-entries"
    end

    local keyType = type(key)
    if keyType ~= "string" and keyType ~= "number" then
      state.seen[value] = nil
      return nil, "unsupported-key-type:"..keyType
    end
    local copiedKey, keyError = deepCopyInternal(key, state, depth + 1)
    if keyError then
      state.seen[value] = nil
      return nil, keyError
    end
    local copiedValue, valueError = deepCopyInternal(child, state, depth + 1)
    if valueError then
      state.seen[value] = nil
      return nil, valueError
    end
    result[copiedKey] = copiedValue
  end
  state.seen[value] = nil
  return result
end

function DataUtils.DeepCopy(value, options)
  options = type(options) == "table" and options or {}
  return deepCopyInternal(value, {
    maxDepth = tonumber(options.maxDepth) or DEFAULT_MAX_DEPTH,
    maxEntries = tonumber(options.maxEntries) or DEFAULT_MAX_ENTRIES,
    entries = 0,
    seen = {},
  }, 1)
end
