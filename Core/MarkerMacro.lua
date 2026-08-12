local _, Addon = ...

local MarkerMacro = {}
Addon.MarkerMacro = MarkerMacro

local DataUtils = Addon.DataUtils

local BULK_TOKEN_HASH_HEX_LENGTH = 16
local BULK_TOKEN_SCHEMA = "batch-v7-compact-combat-guard"
local BULK_MARKER_LIMIT = 3
local COMBAT_GUARD_LINE = "/stopmacro [nocombat]"
local SAFE_IDLE_MACRO = "#showtooltip\n/stopmacro"
local LEGACY_SAFE_IDLE_MACRO = "/stopmacro"

MarkerMacro.BULK_MARKER_LIMIT = BULK_MARKER_LIMIT
MarkerMacro.COMBAT_GUARD_LINE = COMBAT_GUARD_LINE
MarkerMacro.SAFE_IDLE_MACRO = SAFE_IDLE_MACRO
MarkerMacro.LEGACY_SAFE_IDLE_MACRO = LEGACY_SAFE_IDLE_MACRO

local BASE64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local function compactHash(hex)
  if type(hex) ~= "string" or #hex ~= BULK_TOKEN_HASH_HEX_LENGTH or hex:find("[^0-9a-fA-F]") then return nil end
  local bytes = {}
  for index = 1, #hex, 2 do
    bytes[#bytes + 1] = tonumber(hex:sub(index, index + 1), 16)
  end
  local output = {}
  for index = 1, #bytes, 3 do
    local a, b, c = bytes[index], bytes[index + 1], bytes[index + 2]
    output[#output + 1] = BASE64URL:sub(math.floor(a / 4) + 1, math.floor(a / 4) + 1)
    local second = (a % 4) * 16 + math.floor((b or 0) / 16)
    output[#output + 1] = BASE64URL:sub(second + 1, second + 1)
    if b then
      local third = (b % 16) * 4 + math.floor((c or 0) / 64)
      output[#output + 1] = BASE64URL:sub(third + 1, third + 1)
    end
    if c then
      local fourth = c % 64
      output[#output + 1] = BASE64URL:sub(fourth + 1, fourth + 1)
    end
  end
  local value = table.concat(output)
  return #value == 11 and value or nil
end

function MarkerMacro.SanitizeTargetName(value)
  if DataUtils.IsSecret(value) or type(value) ~= "string" then
    return nil, "assignment-target-name-unavailable"
  end
  local name = DataUtils.Trim(value)
  if not name or name == "" then return nil, "assignment-target-name-unavailable" end
  if #name > 120 then return nil, "target-name-too-long" end
  if name:find("[%c%[%];]") then return nil, "unsafe-target-name" end
  return name
end

function MarkerMacro.ParseBulkToken(token)
  token = tostring(token or "")

  local compactBatch, compactSignature = token:match("^([123])([%w_%-]+)$")
  if compactBatch and #compactSignature == 11 then
    return nil, tonumber(compactBatch), nil, nil, compactSignature, "compact"
  end

  local pullIndex, batchIndex, count, signature = token:match("^p(%d+):b([123]):([1-3]):([0-9a-fA-F]+)$")
  if pullIndex and #signature == BULK_TOKEN_HASH_HEX_LENGTH then
    return tonumber(pullIndex), tonumber(batchIndex), nil, tonumber(count), signature:lower(), "signed"
  end

  local legacyPull, legacyBatch, legacyAssignment, legacyCount = token:match("^p(%d+):b([12]):([Ee]%d+:[Cc]%d+):(%d+)$")
  if legacyPull then
    return tonumber(legacyPull), tonumber(legacyBatch), legacyAssignment, tonumber(legacyCount), nil, "legacy-batch"
  end

  local oldPull, oldAssignment, oldCount = token:match("^p(%d+):([Ee]%d+:[Cc]%d+):(%d+)$")
  if oldPull then return tonumber(oldPull), nil, oldAssignment, tonumber(oldCount), nil, "legacy" end
end

function MarkerMacro.BuildBulkToken(identities)
  if type(identities) ~= "table" or #identities == 0 or #identities > BULK_MARKER_LIMIT then return nil end
  local first = identities[1]
  local pullIndex = tonumber(first and first.pullIndex)
  local batchIndex = tonumber(first and first.batchIndex)
  local routeFingerprint = tostring(first and first.routeFingerprint or "")
  if not pullIndex or not batchIndex or batchIndex < 1 or batchIndex > 3 or routeFingerprint == "" then return nil end

  local parts = { BULK_TOKEN_SCHEMA, routeFingerprint, tostring(pullIndex), tostring(batchIndex), tostring(#identities) }
  for _, identity in ipairs(identities) do
    local assignmentID = tostring(identity and identity.assignmentID or "")
    local marker = tonumber(identity and identity.marker)
    local targetName = tostring(identity and identity.targetName or "")
    local executionMethod = tostring(identity and identity.executionMethod or "")
    if assignmentID == "" or assignmentID:find("[^%w:_%-]") or not marker or marker < 1 or marker > 8 or targetName == "" then
      return nil
    end
    parts[#parts + 1] = table.concat({
      assignmentID, tostring(marker), targetName, executionMethod, "set-if-unmarked"
    }, "\31")
  end

  local signature = compactHash(DataUtils.StableHash(table.concat(parts, "\30")))
  if not signature then return nil end
  return tostring(batchIndex)..signature
end

function MarkerMacro.BuildBulkBody(identities)
  if type(identities) ~= "table" or #identities == 0 then return SAFE_IDLE_MACRO end
  if #identities > BULK_MARKER_LIMIT then return nil, "bulk-batch-over-capacity" end
  local batchToken = MarkerMacro.BuildBulkToken(identities)
  if not batchToken then return nil, "bulk-token-invalid" end

  -- The combat guard executes before any protected target/marker command. This
  -- prevents an accidental out-of-combat keypress from changing targets or marks.
  local lines = { COMBAT_GUARD_LINE }
  for _, identity in ipairs(identities) do
    local markerIndex = tonumber(identity.marker)
    if not markerIndex or markerIndex < 1 or markerIndex > 8 then return nil, "invalid-marker" end
    if tostring(identity.executionMethod or "exact-name") ~= "exact-name" then
      return nil, "same-name-automatic-targeting-unavailable"
    end
    local targetName, targetNameError = MarkerMacro.SanitizeTargetName(identity.targetName)
    if not targetName then return nil, targetNameError end
    lines[#lines + 1] = "/cleartarget"
    lines[#lines + 1] = "/targetexact "..targetName
    lines[#lines + 1] = "/tm [harm,nodead] ~"..markerIndex
  end

  lines[#lines + 1] = "/mpm b "..batchToken
  local body = table.concat(lines, "\n")
  if #body > 255 then return nil, "smart-macro-too-long", #body end
  return body
end

local function isRecognizedBulkMacroBody(body)
  if type(body) ~= "string" then return false end
  local lines = {}
  for line in body:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
  if #lines < 2 or #lines > 17 then return false end

  local token = lines[#lines]:match("^/mpm b (.+)$")
  if not token then return false end
  local _, batchIndex, _, count, _, format = MarkerMacro.ParseBulkToken(token)
  if format == "compact" or format == "signed" then
    if not batchIndex then return false end
    if format == "signed" and (not count or count < 1 or count > BULK_MARKER_LIMIT) then return false end
    local lineIndex = lines[1] == COMBAT_GUARD_LINE and 2 or 1
    local assignmentCount = 0
    while lineIndex < #lines do
      local line = lines[lineIndex]
      if line == "/cleartarget" then
        if not lines[lineIndex + 1] or not lines[lineIndex + 1]:match("^/targetexact [^\r\n]+$") then return false end
        local markerLine = lines[lineIndex + 2]
        if not markerLine or (not markerLine:match("^/tm ~[1-8]$")
          and not markerLine:match("^/tm %[harm%] ~[1-8]$")
          and not markerLine:match("^/tm %[harm,nodead%] ~[1-8]$")) then return false end
        assignmentCount = assignmentCount + 1
        lineIndex = lineIndex + 3
      elseif line:match("^/tm %[@mouseover,harm,nodead%] ~[1-8]$")
        or line:match("^/tm %[@target,harm,nodead%] ~[1-8]$") then
        assignmentCount = assignmentCount + 1
        lineIndex = lineIndex + 1
      else
        return false
      end
    end
    if format == "compact" then return assignmentCount >= 1 and assignmentCount <= BULK_MARKER_LIMIT end
    return assignmentCount == count
  end

  if not count or count < 1 or count > BULK_MARKER_LIMIT then return false end
  if format ~= "legacy-batch" and format ~= "legacy" then return false end
  local markerLines = 0
  for index, line in ipairs(lines) do
    if index == #lines then
      -- final legacy /mpm b token already validated above
    elseif line == COMBAT_GUARD_LINE or line == "/cleartarget" then
      -- current guard / legacy safe body
    elseif line:match("^/targetexact [^\r\n]+$") then
      -- legacy exact-name body
    elseif line == "/targetenemy" or line == "/targetenemy 1" then
      -- rc27-rc31 legacy only
    elseif line:match("^/mpm v [12][123]$") then
      -- legacy only
    elseif line:match("^/mpm a p%d+:b[12]:[Ee]%d+:[Cc]%d+:%d+$") then
      -- legacy only
    elseif line:match("^/tm [1-8]$")
      or line:match("^/tm ~[1-8]$")
      or line:match("^/tm %[harm,nodead%] [1-8]$")
      or line:match("^/tm %[harm,nodead%] ~[1-8]$")
      or line:match("^/tm %[@target,harm,nodead%] [1-8]$")
      or line:match("^/tm %[@mouseover,harm,nodead%] [1-8]$") then
      markerLines = markerLines + 1
    else
      return false
    end
  end
  return markerLines >= 1 and markerLines <= BULK_MARKER_LIMIT
end

local LEGACY_CONDITIONS = {
  { marker = 1, modifier = "ctrlshiftalt" },
  { marker = 2, modifier = "ctrlalt" },
  { marker = 3, modifier = "shiftalt" },
  { marker = 4, modifier = "ctrlshift" },
  { marker = 5, modifier = "alt" },
  { marker = 6, modifier = "ctrl" },
  { marker = 7, modifier = "shift" },
  { marker = 8, modifier = nil },
}

local function buildLegacyMacroText(preserveExisting, includeConfirmation)
  local clauses = {}
  for _, option in ipairs(LEGACY_CONDITIONS) do
    local condition = option.modifier and ("mod:"..option.modifier..",") or ""
    local token = preserveExisting and ("~"..option.marker) or tostring(option.marker)
    clauses[#clauses + 1] = ("[%s@mouseover,harm]%s"):format(condition, token)
  end
  local body = "/tm "..table.concat(clauses, ";")
  if includeConfirmation ~= false then body = body.."\n/mpm c" end
  return body
end

function MarkerMacro.IsRecognizedBody(body)
  if type(body) ~= "string" then return false end
  if isRecognizedBulkMacroBody(body) then return true end
  if body == SAFE_IDLE_MACRO or body == "/stopmacro [combat]\n/mpm arm" then return true end
  if body:match("^/stopmacro %[combat%]\n/tm %[@mouseover,harm,nodead%] ~?%d\n/mpm confirm$") then return true end
  if body:match("^/stopmacro %[combat%]\n/stopmacro %[@mouseover,noexists%]%[@mouseover,noharm%]%[@mouseover,dead%]\n/mpm markarm [Ee]%d+:[Cc]%d+\n/tm %[@mouseover,harm,nodead%] ~?%d$") then
    return true
  end
  if body:match("^/stopmacro %[combat%]\n/cleartarget\n/targetexact [^\r\n]+\n/stopmacro %[noexists%]%[noharm%]%[dead%]\n/mpm markarm [Ee]%d+:[Cc]%d+\n/tm ~?%d$") then
    return true
  end
  if body:match("^/stopmacro %[combat%]\n/stopmacro %[@mouseover,noexists%]%[@mouseover,noharm%]%[@mouseover,dead%]\n/tm %[@mouseover,harm,nodead%] ~?%d\n/mpm markdone [Ee]%d+:[Cc]%d+$") then
    return true
  end
  if body:match("^/stopmacro %[combat%]\n/cleartarget\n/targetexact [^\r\n]+\n/stopmacro %[noexists%]%[noharm%]%[dead%]\n/tm ~?%d\n/mpm markdone [Ee]%d+:[Cc]%d+$") then
    return true
  end
  for _, preserveExisting in ipairs({ true, false }) do
    if body == buildLegacyMacroText(preserveExisting, true) or body == buildLegacyMacroText(preserveExisting, false) then return true end
  end
  return false
end
