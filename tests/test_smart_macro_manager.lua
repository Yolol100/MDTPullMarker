local Addon = {
  Constants = {
    SmartButtonName = "MDTPullMarkerSmartButton",
    SmartMacroName = "MDTPM1",
    SmartMacroName2 = "MDTPM2",
  },
  MarkerMacro = {
    SAFE_IDLE_MACRO = "#showtooltip\n/stopmacro",
    LEGACY_SAFE_IDLE_MACRO = "/stopmacro",
  },
}

function Addon.IsSecret(_value)
  return false
end

function Addon.MarkerMacro.IsRecognizedBody(body)
  return body == "UNSAFE-MANAGED-BODY"
    or body == Addon.MarkerMacro.SAFE_IDLE_MACRO
    or body == Addon.MarkerMacro.LEGACY_SAFE_IDLE_MACRO
end

_G.MAX_ACCOUNT_MACROS = 120

local macros = {}
local inCombat = false
local editCalls = 0

function InCombatLockdown()
  return inCombat
end

function GetFileIDFromPath(_path)
  return 134400
end

function GetNumMacros()
  return #macros, 0
end

function GetMacroInfo(index)
  local row = macros[index]
  if not row then return nil end
  return row.name, row.icon, row.body
end

function EditMacro(index, _name, icon, body)
  editCalls = editCalls + 1
  local row = assert(macros[index], "EditMacro received unknown macro index")
  row.icon = icon
  row.body = body
  return index
end

function CreateMacro()
  error("CreateMacro must not be called by these parking tests")
end

function DeleteMacro()
  error("DeleteMacro must not be called by these parking tests")
end

local chunk = assert(loadfile("Runtime/SmartMacroManager.lua"))
chunk("MDTPullMarker", Addon)
assert(Addon.SmartMacroManager, "SmartMacroManager factory was not loaded")

local function newManager()
  return Addon.SmartMacroManager:Create({
    desiredBody = function()
      return Addon.MarkerMacro.SAFE_IDLE_MACRO
    end,
    dungeonSessionActive = function()
      return false
    end,
    log = function() end,
    macroNames = { "MDTPM1", "MDTPM2" },
  })
end

local function resetMacros(rows)
  macros = rows or {}
  editCalls = 0
  inCombat = false
end

-- Behavioural proof: combat lockdown must never write protected macro state.
resetMacros({
  { name = "MDTPM1", icon = 134400, body = "UNSAFE-MANAGED-BODY" },
})
local manager = newManager()
inCombat = true
local parked, reason = manager:ParkAllManagedExecution("combat-test")
assert(parked == false, "parking must fail closed during combat")
assert(reason == "in-combat", "combat parking must report in-combat")
assert(manager:IsPending() == true, "combat parking must mark a pending refresh")
assert(editCalls == 0, "combat parking must not call EditMacro")
assert(macros[1].body == "UNSAFE-MANAGED-BODY", "combat parking must not mutate macro body")

-- Behavioural proof: out of combat, recognized managed execution is parked and
-- then read back through GetMacroInfo before success is returned.
resetMacros({
  { name = "MDTPM1", icon = 134400, body = "UNSAFE-MANAGED-BODY" },
  { name = "OtherMacro", icon = 134400, body = "UNSAFE-MANAGED-BODY" },
})
manager = newManager()
parked, reason = manager:ParkAllManagedExecution("route-invalidated")
assert(parked == true, "recognized managed macro should park successfully")
assert(reason == 1, "exactly one managed macro should be parked")
assert(editCalls == 1, "only the reserved managed macro may be edited")
assert(macros[1].body == Addon.MarkerMacro.SAFE_IDLE_MACRO, "managed macro must be parked")
assert(macros[2].body == "UNSAFE-MANAGED-BODY", "unmanaged macro must remain untouched")
assert(manager:IsPending() == false, "successful parking must not create pending state")

print("ok - smart macro manager behavioral parking and combat guards")
