local _, Addon = ...

local Integration = {}
Addon.MDTIntegration = Integration

local SECTION_KEY = "mdtpullmarker"
local state = {
  registered = false, attached = false, lastError = nil, plugin = nil, panel = nil,
  mode = "none", pendingSection = nil, legacyFrameCallbackRegistered = false,
}

local function copyStatus()
  return { registered = state.registered, attached = state.attached, lastError = state.lastError, sectionKey = SECTION_KEY, mode = state.mode }
end
local function setError(message)
  state.lastError = tostring(message or "unknown-error")
  if Addon.Log then Addon.Log("WARN", "MDT UI integration: "..state.lastError, false) end
  return nil, state.lastError
end
local function setPending(message) state.lastError = tostring(message or "pending") return nil, state.lastError end
local function getPublicAPI() local api = _G.MythicDungeonToolsAPI if type(api) == "table" then return api end end
local function getLegacyMDT() local legacy = _G.MDT if type(legacy) == "table" then return legacy end end
local function legacySectionExists(legacy, key)
  if type(legacy.GetNavigationSection) == "function" then local ok, section = pcall(legacy.GetNavigationSection, legacy, key) if ok then return section end end
  local lookup = legacy.navigationSectionLookup return type(lookup) == "table" and lookup[key] or nil
end
local function makeLegacyPlugin(legacy)
  local plugin = { legacy = legacy }
  function plugin:RegisterNavigationSection(section) local existing = legacySectionExists(legacy, section.key) if existing then return existing end return legacy:RegisterNavigationSection(section) end
  function plugin:GetNavigationSectionContentFrame(key) local frame = legacy.main_frame local frames = frame and frame.sectionContentFrames return type(frames) == "table" and frames[key] or nil end
  function plugin:SetCurrentSection(key) return legacy:SetCurrentSection(key) end
  return plugin
end
local function applyPendingSection()
  local sectionKey, plugin = state.pendingSection, state.plugin
  if not sectionKey or type(plugin) ~= "table" or type(plugin.SetCurrentSection) ~= "function" then return end
  local ok, sectionError = pcall(plugin.SetCurrentSection, plugin, sectionKey)
  if ok then state.pendingSection = nil else setError("set-section-failed:"..tostring(sectionError)) end
end

function Integration:BuildPanel()
  if state.panel then if Addon.ConfigurationUI then Addon.ConfigurationUI:Refresh() end return state.panel end
  local plugin = state.plugin
  if type(plugin) ~= "table" or type(plugin.GetNavigationSectionContentFrame) ~= "function" then return setError("content-frame-api-unavailable") end
  local parent = plugin:GetNavigationSectionContentFrame(SECTION_KEY)
  if not parent then return setPending("content-frame-pending") end
  if not Addon.ConfigurationUI or type(Addon.ConfigurationUI.CreateEmbedded) ~= "function" then return setError("configuration-ui-unavailable") end
  local panel, panelError = Addon.ConfigurationUI:CreateEmbedded(parent)
  if not panel then return setError(panelError or "embedded-panel-failed") end
  state.panel, state.lastError = panel, nil
  Addon.ConfigurationUI:Refresh()
  return panel
end
function Integration:Attach(plugin, mode)
  if state.attached then applyPendingSection() return true end
  if type(plugin) ~= "table" then return setError("invalid-plugin-api") end
  if type(plugin.RegisterNavigationSection) ~= "function" or type(plugin.GetNavigationSectionContentFrame) ~= "function" or type(plugin.SetCurrentSection) ~= "function" then
    return setError("required-plugin-method-missing")
  end
  state.plugin, state.mode = plugin, mode or state.mode or "unknown"
  local ok, result = pcall(plugin.RegisterNavigationSection, plugin, {
    key = SECTION_KEY, name = "Pull Markers", tooltip = "Route-bound target markers for the active MDT route",
    texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", texCoords = { 0, 1, 0, 1 }, iconSize = 27,
    createContentFrame = true, createSidePanelFrame = false,
    onShow = function() Integration:BuildPanel() end,
  })
  if not ok then return setError("register-section-failed:"..tostring(result)) end
  state.attached, state.lastError = true, nil
  applyPendingSection()
  return true
end
local function registerPublic(api)
  local ok, registrationError = pcall(api.RegisterUIInitializer, api, function(plugin)
    local attached, attachError = Integration:Attach(plugin, "public-plugin")
    if not attached and Addon.Chat then Addon.Chat("MDT integration unavailable: "..tostring(attachError)) end
  end)
  if not ok then return nil, "initializer-registration-failed:"..tostring(registrationError) end
  state.registered, state.mode, state.lastError = true, "public-plugin", nil
  return true
end
local function registerLegacy(legacy)
  if type(legacy.RegisterNavigationSection) ~= "function" or type(legacy.SetCurrentSection) ~= "function" then return nil, "legacy-navigation-api-unavailable" end
  local existing = legacySectionExists(legacy, SECTION_KEY)
  if legacy.main_frame and not existing then
    state.registered, state.mode, state.lastError = true, "legacy-standalone-fallback", "legacy-ui-already-initialized"
    if Addon.Log then Addon.Log("INFO", "MDT UI was already initialized; using the standalone Pull Marker window.", false) end
    return nil, state.lastError
  end
  local attached, attachError = Integration:Attach(makeLegacyPlugin(legacy), "legacy-direct")
  if not attached then return nil, attachError end
  state.registered, state.lastError = true, nil
  if not state.legacyFrameCallbackRegistered and type(legacy.RunAfterFramesInitialized) == "function" then
    state.legacyFrameCallbackRegistered = true
    local ok, callbackError = pcall(legacy.RunAfterFramesInitialized, legacy, function() Integration:BuildPanel() applyPendingSection() end)
    if not ok then state.legacyFrameCallbackRegistered = false if Addon.Log then Addon.Log("WARN", "MDT frame-ready callback failed: "..tostring(callbackError), false) end end
  end
  return true
end
function Integration:Register()
  if state.registered and (state.attached or state.mode == "public-plugin") then return true end
  if state.registered and state.mode == "legacy-standalone-fallback" then return nil, state.lastError or "legacy-ui-already-initialized" end
  local api = getPublicAPI()
  if type(api) == "table" and type(api.RegisterUIInitializer) == "function" then
    local registered, registrationError = registerPublic(api)
    if registered then return true end
    if Addon.Log then Addon.Log("WARN", "Public MDT UI registration failed: "..tostring(registrationError), false) end
  end
  local legacy = getLegacyMDT()
  if legacy then
    local registered, registrationError = registerLegacy(legacy)
    if registered then return true end
    if registrationError == "legacy-ui-already-initialized" then return nil, registrationError end
    return setError(registrationError)
  end
  return setError("mdt-ui-integration-unavailable")
end
local function showMDT()
  local api = getPublicAPI()
  if type(api) == "table" and type(api.ShowInterface) == "function" then local ok, showError = pcall(api.ShowInterface, api, true) if not ok then return nil, "show-mdt-failed:"..tostring(showError) end return true end
  local legacy = getLegacyMDT()
  if type(legacy) == "table" and type(legacy.ShowInterface) == "function" then local ok, showError = pcall(legacy.ShowInterface, legacy, true) if not ok then return nil, "show-mdt-failed:"..tostring(showError) end return true end
  return nil, "mdt-interface-unavailable"
end
local function requestSection(sectionKey) state.pendingSection = sectionKey if state.attached then applyPendingSection() end end
function Integration:OpenSection()
  requestSection(SECTION_KEY)
  local registered, registrationError = self:Register()
  if not registered then state.pendingSection = nil return nil, registrationError end
  local shown, showError = showMDT(); if not shown then return setError(showError) end
  applyPendingSection(); return true
end
local function setNamedSection(sectionKey)
  local plugin = state.plugin
  if state.attached and type(plugin) == "table" and type(plugin.SetCurrentSection) == "function" then
    local ok, sectionError = pcall(plugin.SetCurrentSection, plugin, sectionKey); if not ok then return nil, "set-section-failed:"..tostring(sectionError) end
    state.pendingSection = nil; return true
  end
  local legacy = getLegacyMDT()
  if type(legacy) == "table" and type(legacy.SetCurrentSection) == "function" then
    local section = legacySectionExists(legacy, sectionKey); if not section then return nil, "mdt-section-unavailable:"..tostring(sectionKey) end
    local ok, sectionError = pcall(legacy.SetCurrentSection, legacy, sectionKey); if not ok then return nil, "set-section-failed:"..tostring(sectionError) end
    state.pendingSection = nil; return true
  end
  return nil, "mdt-section-api-unavailable"
end
function Integration:OpenNamedSection(sectionKey)
  sectionKey = tostring(sectionKey or ""); if sectionKey == "" then return setError("section-key-missing") end
  requestSection(sectionKey)
  local registered, registrationError = self:Register()
  if not registered and registrationError ~= "legacy-ui-already-initialized" then state.pendingSection = nil return nil, registrationError end
  local shown, showError = showMDT(); if not shown then return setError(showError) end
  local selected, sectionError = setNamedSection(sectionKey); if not selected then return setError(sectionError) end
  return true
end
function Integration:OpenMap() local opened, openError = self:OpenNamedSection("maps") if opened and Addon.MDT then Addon.MDT:Refresh("open-mdt-map") end return opened, openError end
function Integration:OpenFocusMarkers() return self:OpenNamedSection("marks") end
function Integration:GetStatus() return copyStatus() end
