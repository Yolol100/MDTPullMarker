local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[deepCopy(key, seen)] = deepCopy(item, seen) end
  return result
end

local focusDB = {
  focusMarker = {
    lastMarker = 8,
    assignments = {},
    useMacro = false,
    preserveExistingTargetMarkers = true,
  },
}
local keyMode = "separate"

_G.MythicDungeonToolsAPI = {
  GetDB = function() return focusDB end,
}
_G.MDT = nil
_G.MythicDungeonToolsDB = nil
_G.GetBindingKey = function(command)
  if keyMode == "same" then return "F1" end
  if command == "CLICK MDTFocusMarkerButton:LeftButton" then return "F1" end
  if command == "CLICK MDTPullMarkerSmartButton:LeftButton" then return "F2" end
end
_G.GetMacroIndexByName = function(name)
  if focusDB.focusMarker.useMacro and name == (focusDB.focusMarker.macroName or "MDTFocusMarker") then return 1 end
  return 0
end
_G.GetMacroInfo = function(index)
  if index == 1 then return focusDB.focusMarker.macroName or "MDTFocusMarker", 134400, "/focus" end
end
_G.InCombatLockdown = function() return false end

local Addon = {
  Constants = {
    SmartButtonName = "MDTPullMarkerSmartButton",
    SmartMacroName = "MDTPM1",
    SmartMacroName2 = "MDTPM2",
    MarkerNames = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" },
  },
  IsSecret = function() return false end,
  DataUtils = { DeepCopy = deepCopy },
  Database = {
    GetGlobal = function() return { preserveExistingMarkers = true } end,
  },
  RuntimeController = {
    GetState = function() return { currentPullIndex = 1 } end,
  },
  MarkerPlanner = {
    Build = function()
      return {
        pulls = {
          { index = 1, assignments = { { marker = 8 } } },
        },
      }
    end,
  },
}

local chunk, loadError = loadfile("Integrations/MDTFocusMarkerBridge.lua")
assert(chunk, loadError)
chunk("MDTPullMarker", Addon)
local Bridge = assert(Addon.MDTFocusMarkerBridge, "bridge did not register")

local overlap = Bridge:Refresh({ pulls = {} })
assert(overlap.available == true, "MDT Focus Marker settings should be detected through the public API")
assert(overlap.code == "focus-current-pull-overlap", "shared current-pull icons must be reported")
assert(overlap.currentPullOverlap[1] == 8, "Skull overlap must be identified")

focusDB.focusMarker.lastMarker = 7
local safe = Bridge:Refresh({ pulls = {} })
assert(safe.code == "cooperation-safe", "separate marker icons and keybinds should remain compatible")
assert(#safe.currentPullOverlap == 0 and #safe.bindingOverlap == 0)

keyMode = "same"
local keyConflict = Bridge:Refresh({ pulls = {} })
assert(keyConflict.code == "focus-keybind-conflict", "shared secure-action keybinds must fail the cooperation check")
assert(keyConflict.bindingOverlap[1] == "F1")

keyMode = "separate"
focusDB.focusMarker.useMacro = true
focusDB.focusMarker.macroName = "MDTPM1"
local macroConflict = Bridge:Refresh({ pulls = {} })
assert(macroConflict.code == "focus-macro-name-conflict", "Focus Marker must not reuse a Pull Marker macro name")
assert(macroConflict.macroNameConflict == true)

print("ok - MDT Focus Marker marker, keybind, and macro cooperation")
