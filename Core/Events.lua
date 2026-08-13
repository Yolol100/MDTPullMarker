local addonName, Addon = ...

local Events = {}
Addon.Events = Events

local eventFrame = CreateFrame("Frame")
local initialized = false
local initializing = false

local SESSION_EVENTS = {
  PLAYER_ENTERING_WORLD = true,
  PLAYER_MAP_CHANGED = true,
  ZONE_CHANGED_NEW_AREA = true,
  PLAYER_DIFFICULTY_CHANGED = true,
  CHALLENGE_MODE_START = true,
  CHALLENGE_MODE_RESET = true,
  CHALLENGE_MODE_COMPLETED = true,
  CHALLENGE_MODE_MAPS_UPDATE = true,
  UPDATE_INSTANCE_INFO = true,
}

local function refreshVisibleUI()
  if Addon.ConfigurationUI:HasViews() then Addon.ConfigurationUI:Refresh() end
  if Addon.RuntimeFrame:IsOpen() then Addon.RuntimeFrame:Refresh() end
end

local function initializeAddon()
  if initialized then return true end
  if initializing then return nil, "initialization-in-progress" end
  initializing = true

  local databaseReady, databaseError
  local ok, runtimeError = pcall(function()
    databaseReady, databaseError = Addon.Database.Initialize(_G.MDTPullMarkerDB)
    Addon.MarkerExecutor:Initialize()
    Addon.MDT:Initialize()
    Addon.RuntimeController:Initialize()
    Addon.PullDeathTracker:Initialize()
    Addon.MarkerOwnership:Initialize()
    Addon.DungeonSession:Refresh("addon-loaded", false)
    Addon.MDTFocusMarkerBridge:Refresh()
    Addon.MDTIntegration:Register()
  end)
  initializing = false

  if not ok then
    Addon.Log("ERROR", "Addon initialization failed and will retry at PLAYER_LOGIN: "..tostring(runtimeError), false)
    return nil, "initialization-failed"
  end

  initialized = true
  if databaseReady then
    Addon.Log("INFO", "Addon database loaded.", false)
  else
    Addon.Log("ERROR", "Database started in memory-only mode: "..tostring(databaseError), false)
  end
  return databaseReady, databaseError
end

local function handleEvent(_, event, ...)
  if event == "ADDON_LOADED" then
    local loadedAddon = ...
    if loadedAddon == addonName then
      initializeAddon()
      return
    end
    if initialized and loadedAddon == "MythicDungeonTools_UI" then
      Addon.RuntimeController:Refresh("addon-loaded:MythicDungeonTools_UI")
      Addon.MDTFocusMarkerBridge:Refresh()
      Addon.MDTIntegration:Register()
      refreshVisibleUI()
    end
    return
  end

  if not initialized and event == "PLAYER_LOGIN" then
    initializeAddon()
  end
  if not initialized then return end

  if event == "PLAYER_LOGIN" then
    Addon.RuntimeController:Refresh("player-login")
    Addon.MarkerOwnership:OnWorldChanged("player-login")
    Addon.DungeonSession:ScheduleRefresh("player-login", 1, true)
    Addon.MDTFocusMarkerBridge:Refresh()
    Addon.MDTIntegration:Register()

    local global = Addon.GetGlobal and Addon.GetGlobal()
    if global and global.firstRun then
      local updated, updateError = Addon.Database.SetGlobal("firstRun", false)
      if not updated then
        Addon.Log("WARN", "First-run status could not be saved: "..tostring(updateError), false)
      end
      Addon.Chat((Addon.L and Addon.L.READY_AUTOMATIC) or "Ready. MDT Pull Marker activates automatically when you enter a dungeon.")
    end
  elseif event == "CHAT_MSG_ADDON" then
    Addon.MarkerOwnership:OnAddonMessage(...)
  elseif event == "PLAYER_REGEN_DISABLED" then
    Addon.PullDeathTracker:OnCombatStarted()
    Addon.MarkerOwnership:OnCombatStarted()
  elseif SESSION_EVENTS[event] then
    -- Invalidate/park the old dungeon context before ownership or any delayed
    -- enrichment can observe it as executable.
    Addon.DungeonSession:OnEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then Addon.MarkerOwnership:OnWorldChanged(event) end
  elseif event == "READY_CHECK" then
    Addon.MDTFocusMarkerBridge:Refresh()
    refreshVisibleUI()
  elseif event == "CVAR_UPDATE" then
    Addon.MarkerExecutor:OnCVarUpdate(...)
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    Addon.PullDeathTracker:OnCombatLogEvent()
  elseif event == "RAID_TARGET_UPDATE" then
    Addon.MarkerExecutor:OnRaidTargetUpdate()
  elseif event == "UPDATE_MACROS" then
    Addon.MarkerExecutor:OnMacroListChanged()
    Addon.MDTFocusMarkerBridge:Refresh()
    refreshVisibleUI()
  elseif event == "UPDATE_BINDINGS" then
    Addon.MDTFocusMarkerBridge:Refresh()
    refreshVisibleUI()
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PARTY_LEADER_CHANGED" then
    Addon.MarkerOwnership:OnGroupChanged(event)
    Addon.MDTFocusMarkerBridge:Refresh()
    refreshVisibleUI()
  elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
    Addon.ConfigurationUI:OnDisplayChanged()
    Addon.RuntimeFrame:OnDisplayChanged()
  elseif event == "PLAYER_REGEN_ENABLED" then
    Addon.MarkerExecutor:OnCombatEnded()
    Addon.MarkerOwnership:OnCombatEnded()
    Addon.DungeonSession:ScheduleRefresh("combat-ended", 0, true)
  end
end

for _, event in ipairs({
  "ADDON_LOADED",
  "PLAYER_LOGIN",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_REGEN_DISABLED",
  "READY_CHECK",
  "UPDATE_BINDINGS",
  "UPDATE_MACROS",
  "CVAR_UPDATE",
  "COMBAT_LOG_EVENT_UNFILTERED",
  "RAID_TARGET_UPDATE",
  "GROUP_ROSTER_UPDATE",
  "PLAYER_ROLES_ASSIGNED",
  "PARTY_LEADER_CHANGED",
  "CHAT_MSG_ADDON",
  "DISPLAY_SIZE_CHANGED",
  "UI_SCALE_CHANGED",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_MAP_CHANGED",
  "ZONE_CHANGED_NEW_AREA",
  "PLAYER_DIFFICULTY_CHANGED",
  "CHALLENGE_MODE_START",
  "CHALLENGE_MODE_RESET",
  "CHALLENGE_MODE_COMPLETED",
  "CHALLENGE_MODE_MAPS_UPDATE",
  "UPDATE_INSTANCE_INFO",
}) do
  eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(frame, event, ...)
  local _, eventError = Addon.ErrorHandler.Run("event:"..tostring(event), handleEvent, frame, event, ...)
  if eventError and eventError.code then
    Addon.Log("ERROR", "Event "..tostring(event).." failed: "..tostring(eventError.code), false)
  end
end)
