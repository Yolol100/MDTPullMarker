local _, Addon = ...

local L = Addon.L or {}

local UI = {}
Addon.ConfigurationUI = UI

local state = { standalone = nil, views = {}, model = nil, lastError = nil }
local COLORS = { background = { 0.0588, 0.0588, 0.0588, 0.98 }, panel = { 0.09, 0.09, 0.09, 0.98 }, border = { 1, 1, 1, 0.10 }, gold = { 1, 0.8196, 0, 1 } }
local function setBackdrop(frame, color)
  if not frame or not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  frame:SetBackdropColor(unpack(color or COLORS.panel)); frame:SetBackdropBorderColor(unpack(COLORS.border))
end
local function makeText(parent, template) return parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal") end
local function makeButton(parent, label, width, callback) local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") button:SetSize(width or 132, 30) button:SetText(label) button:SetScript("OnClick", callback) return button end
local function applySavedPosition(frame) frame:ClearAllPoints() local position = Addon.Database.GetUIPosition("configuration") if position then frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y) else frame:SetPoint("CENTER") end end
local function savePosition(frame) if not frame.GetPoint then return end local point, _, relativePoint, x, y = frame:GetPoint(1) if point and relativePoint then Addon.Database.SaveUIPosition("configuration", { point = point, relativePoint = relativePoint, x = x or 0, y = y or 0 }) end end
local function inCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end
local function activeRouteBinding() return Addon.MDT and type(Addon.MDT.GetRouteBinding) == "function" and Addon.MDT:GetRouteBinding() or nil end
local function routeBindingCount() if not (Addon.MDT and type(Addon.MDT.GetRouteBindings) == "function") then return 0 end local count = 0 for _ in pairs(Addon.MDT:GetRouteBindings() or {}) do count = count + 1 end return count end
local function macroProblem(status) local err = status and status.error if not err then return nil end if tostring(err):find("^reserved%-macro%-name%-conflict:") then return "Macro name conflict - rename the existing "..tostring(status.name or "MDTPM macro") end return "Macro check failed" end
local function macroActionError(err) err = tostring(err or "") if err:find("reserved%-macro%-name%-conflict:") then return "Rename or delete the unrelated MDTPM/MPM macro first. It will not be overwritten." end return "Macro is not ready. Use /mpm doctor if this keeps happening." end

function UI:BuildViewModel()
  local snapshot = Addon.MDT:Refresh("simple-ui-refresh") or Addon.MDT:GetSnapshot()
  local binding = activeRouteBinding()
  if snapshot and binding and not inCombat() then local runtime = Addon.RuntimeController:Refresh("simple-ui-refresh", true) if runtime then Addon.MarkerExecutor:RefreshRouteMacros("simple-ui-refresh") end end
  local plan = snapshot and Addon.MDT:BuildMarkerPlan() or nil
  local executorState = Addon.MarkerExecutor:GetState(); local runtimeState = Addon.RuntimeController:GetState(); local sessionState = Addon.DungeonSession:GetState()
  local model = { available = snapshot ~= nil, routeName = snapshot and (snapshot.presetName or (L.ACTIVE_MDT_ROUTE or "Active MDT route")) or nil, dungeonName = snapshot and snapshot.dungeonName or nil,
    markerCount = plan and plan.summary and tonumber(plan.summary.assignments) or 0, planStatus = plan and plan.status or "unavailable",
    macro1 = executorState.smartMacros and executorState.smartMacros[1] or {}, macro2 = executorState.smartMacros and executorState.smartMacros[2] or {},
    routeBinding = binding, routeMacros = executorState.routeMacros or {}, executor = executorState, runtime = runtimeState, dungeonActive = sessionState.active == true, combat = inCombat() }
  state.model = model; return model
end

local function pickupMacro(index)
  if inCombat() then state.lastError = "Leave combat first to place or update macros." UI:Refresh() return end
  local binding = activeRouteBinding(); local session = Addon.DungeonSession:GetState()
  if not binding and session.active ~= true then state.lastError = "Bind an MDT route first, or enter the dungeon for legacy macro mode." UI:Refresh() return end
  local snapshot, snapshotError = Addon.MDT:Refresh("ui-macro-pickup", { allowUILoad = true })
  if not snapshot then state.lastError = "Open the correct MDT route first." Addon.Log("WARN", "UI macro pickup route refresh failed: "..tostring(snapshotError), false) UI:Refresh() return end
  local runtime, runtimeError = Addon.RuntimeController:Refresh("ui-macro-pickup", true)
  if not runtime then state.lastError = "Marker plan is not ready. Use /mpm doctor for details." Addon.Log("WARN", "UI macro pickup runtime refresh failed: "..tostring(runtimeError), false) UI:Refresh() return end
  Addon.DungeonSession:Refresh("ui-macro-pickup", false)
  local results, macroError
  if binding then
    local current = Addon.RuntimeController:GetState(); local descriptor = Addon.RuntimeController:GetRouteMacroDescriptor(current.currentPullIndex, index)
    if not descriptor then state.lastError = index == 2 and "This pull does not need a B macro." or "This pull has no automatic marker macro." UI:Refresh() return end
    results, macroError = Addon.MarkerExecutor:EnsureRouteMacros(current.currentPullIndex, index)
  else results, macroError = Addon.MarkerExecutor:EnsureSmartMacros(index) end
  if not results then state.lastError = macroActionError(macroError) Addon.Log("WARN", "Macro pickup failed: "..tostring(macroError), false) else state.lastError = nil end
  UI:Refresh()
end

local function bindSelectedRoute()
  if inCombat() then state.lastError = "Leave combat first to bind a route." UI:Refresh() return end
  local binding, bindError = Addon.MDT:BindCurrentRoute()
  if not binding then state.lastError = "Could not bind the selected MDT route: "..tostring(bindError or "route unavailable") UI:Refresh() return end
  local runtime, runtimeError = Addon.RuntimeController:Refresh("ui-route-bound", true)
  if not runtime then state.lastError = "Route bound, but marker plan failed: "..tostring(runtimeError) UI:Refresh() return end
  local macros, macroError = Addon.MarkerExecutor:RefreshRouteMacros("ui-route-bound")
  if not macros then state.lastError = "Route bound, but macros failed: "..tostring(macroError) else state.lastError = nil end
  UI:Refresh()
end
local function unbindSelectedRoute()
  if inCombat() then state.lastError = "Leave combat first to unbind the route." UI:Refresh() return end
  local cleared, clearError = Addon.MDT:ClearRouteBinding()
  if not cleared then state.lastError = "Could not clear route binding: "..tostring(clearError) UI:Refresh() return end
  local remainingBindings = routeBindingCount(); local cleaned, cleanupError
  if remainingBindings > 0 then cleaned, cleanupError = Addon.MarkerExecutor:ParkRouteMacros("ui-route-unbound-other-dungeons-remain") else cleaned, cleanupError = Addon.MarkerExecutor:RetireRouteMacros("ui-route-unbound-last-binding") end
  Addon.RuntimeController:Refresh("ui-route-unbound", true); Addon.MarkerExecutor:OnInstructionChanged("route-unbound")
  state.lastError = not cleaned and cleanupError ~= "delete-macro-unavailable" and cleanupError ~= "edit-macro-unavailable" and ("Route unbound, but cleanup failed: "..tostring(cleanupError)) or nil
  UI:Refresh()
end

local function refreshView(view, model)
  if model.available then local label = model.routeName or (L.ACTIVE_MDT_ROUTE or "Active MDT route") if model.dungeonName and model.dungeonName ~= label then label = label.." • "..model.dungeonName end view.route:SetText((model.routeBinding and "Bound: " or "Selected: ")..label.." • "..tostring(model.markerCount or 0).." markers") else view.route:SetText((L.OPEN_CORRECT_ROUTE or "Open the correct route in MDT")) end
  local bound = model.routeBinding ~= nil; local routeMacros = model.routeMacros or {}; local problem = bound and routeMacros.conflictCount and routeMacros.conflictCount > 0 and "Route macro name conflict" or (model.dungeonActive and (macroProblem(model.macro1) or macroProblem(model.macro2)) or nil)
  if bound and problem then view.macro:SetText("|cffff5959"..problem.."|r")
  elseif bound and routeMacros.desiredCount == 0 then view.macro:SetText("|cffffad33Bound route has no automatic marker macros|r")
  elseif bound and routeMacros.current and routeMacros.executionActive == false then view.macro:SetText(("|cffb8b8b8Route macros ready but inactive: %d/%d|r"):format(routeMacros.currentCount or 0, routeMacros.desiredCount or 0))
  elseif bound and routeMacros.current then view.macro:SetText(("|cff59df80Route macros active: %d/%d|r"):format(routeMacros.currentCount or 0, routeMacros.desiredCount or 0))
  elseif bound and model.combat then view.macro:SetText("|cffffad33Route macros update after combat|r")
  elseif bound then view.macro:SetText(("|cffffad33Preparing route macros: %d/%d|r"):format(routeMacros.currentCount or 0, routeMacros.desiredCount or 0))
  elseif not model.dungeonActive then view.macro:SetText(("|cffb8b8b8"..(L.WAITING_FOR_DUNGEON or "Waiting for dungeon").."|r"))
  elseif problem then view.macro:SetText("|cffff5959"..problem.."|r")
  elseif model.runtime and model.runtime.automaticTargeting == false then view.macro:SetText(("|cffffad33"..(L.SAME_NAME_PARKED or "Same-name pull parked safely").."|r"))
  elseif model.macro1.current and model.macro2.current then view.macro:SetText("|cff59df80Macros ready: MDTPM1 + MDTPM2|r")
  elseif model.combat then view.macro:SetText(("|cffffad33"..(L.MACROS_UPDATE_AFTER_COMBAT or "Macros update after combat").."|r")) else view.macro:SetText(("|cffffad33"..(L.PREPARING_MACROS or "Preparing macros...").."|r")) end

  if not bound then view.guide:SetText("Select the route you want in MDT, then click Bind route. Legacy mode still activates automatically in a dungeon.")
  elseif model.planStatus == "blocked" then view.guide:SetText("|cffff5959This pull can’t be marked automatically. Run /mpm doctor for details.|r")
  elseif model.planStatus == "unavailable" then view.guide:SetText("|cffff5959Marker plan isn’t ready. Run /mpm doctor for details.|r")
  else
    if bound then
      local pullIndex = model.runtime and model.runtime.currentPullIndex; local a = pullIndex and Addon.RuntimeController:GetRouteMacroDescriptor(pullIndex, 1) or nil; local b = pullIndex and Addon.RuntimeController:GetRouteMacroDescriptor(pullIndex, 2) or nil; local c = pullIndex and Addon.RuntimeController:GetRouteMacroDescriptor(pullIndex, 3) or nil
      local text = a and ("Pull "..tostring(pullIndex)..": "..a.name) or ("Pull "..tostring(pullIndex or "?")..": manual/no marker macro")
      if b then text = text.."  ->  wait ~4 sec  ->  "..b.name end; if c then text = text.."  ->  wait ~4 sec  ->  "..c.name end
      view.guide:SetText(text..". You may use a later pull macro early for a chain-pull.")
    else
      local submission = model.executor and model.executor.bulkSubmission; local flowText = submission and submission.batch2Required and "MDTPM1  ->  wait ~4 sec  ->  MDTPM2" or "MDTPM1"
      if submission and submission.allRequired then flowText = "Markers submitted • next marked pull loads after combat" elseif submission and submission.batch1 and submission.batch2Required then flowText = "MDTPM1 submitted  ->  wait ~4 sec  ->  MDTPM2" elseif submission and submission.batch1 and not submission.batch2Required then flowText = "MDTPM1 submitted • next marked pull loads after combat" end
      local targetingText = model.runtime and model.runtime.automaticTargeting == false and Addon.Constants.AutomaticTargetingWarning or nil
      view.guide:SetText(targetingText or flowText)
    end
  end
  if bound or model.dungeonActive then view.pick1:Show(); view.pick2:Show() else view.pick1:Hide(); view.pick2:Hide() end
  if bound then view.pick3:Show() else view.pick3:Hide() end
  view.pick1:SetText(bound and "Pick up A macro" or "Pick up marker macro 1"); view.pick2:SetText(bound and "Pick up B macro" or "Pick up marker macro 2"); view.pick3:SetText("Pick up C macro")
  view.pick1:SetEnabled((bound or model.dungeonActive) and not model.combat); view.pick2:SetEnabled((bound or model.dungeonActive) and not model.combat); view.pick3:SetEnabled(bound and not model.combat); view.bind:SetEnabled(not model.combat); view.unbind:SetEnabled(bound and not model.combat)
  view.error:SetText(state.lastError and ("|cffffad33"..state.lastError.."|r") or "")
end

local function createEditor(parent)
  local root = CreateFrame("Frame", nil, parent, "BackdropTemplate"); root:SetAllPoints(parent); setBackdrop(root, COLORS.background)
  local title = makeText(root, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 20, -20); title:SetText(L.CONFIG_TITLE or L.ADDON_NAME or "MDT Pull Marker"); title:SetTextColor(unpack(COLORS.gold))
  local route = makeText(root, "GameFontHighlight"); route:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16); route:SetPoint("RIGHT", -20, 0); route:SetJustifyH("LEFT")
  local macro = makeText(root, "GameFontHighlight"); macro:SetPoint("TOPLEFT", route, "BOTTOMLEFT", 0, -10); macro:SetPoint("RIGHT", -20, 0); macro:SetJustifyH("LEFT")
  local guide = makeText(root, "GameFontNormal"); guide:SetPoint("TOPLEFT", macro, "BOTTOMLEFT", 0, -22); guide:SetPoint("RIGHT", -20, 0); guide:SetJustifyH("LEFT")
  local openMap = makeButton(root, "Open MDT map", 145, function() local opened = Addon.MDTIntegration and Addon.MDTIntegration:OpenMap() if not opened then state.lastError = "Could not open the MDT map." UI:Refresh() end end); openMap:SetPoint("TOPLEFT", guide, "BOTTOMLEFT", 0, -20)
  local bind = makeButton(root, "Bind route", 150, bindSelectedRoute); bind:SetPoint("LEFT", openMap, "RIGHT", 8, 0)
  local unbind = makeButton(root, "Unbind route", 110, unbindSelectedRoute); unbind:SetPoint("LEFT", bind, "RIGHT", 8, 0)
  local pick1 = makeButton(root, "Pick up marker macro 1", 140, function() pickupMacro(1) end); pick1:SetPoint("TOPLEFT", openMap, "BOTTOMLEFT", 0, -10)
  local pick2 = makeButton(root, "Pick up marker macro 2", 140, function() pickupMacro(2) end); pick2:SetPoint("LEFT", pick1, "RIGHT", 8, 0)
  local pick3 = makeButton(root, "Pick up C macro", 140, function() pickupMacro(3) end); pick3:SetPoint("LEFT", pick2, "RIGHT", 8, 0); pick3:Hide()
  local errorText = makeText(root, "GameFontHighlightSmall"); errorText:SetPoint("TOPLEFT", pick1, "BOTTOMLEFT", 0, -14); errorText:SetPoint("RIGHT", -20, 0); errorText:SetJustifyH("LEFT")
  local view = { root = root, route = route, macro = macro, guide = guide, bind = bind, unbind = unbind, pick1 = pick1, pick2 = pick2, pick3 = pick3, error = errorText }
  state.views[#state.views + 1] = view; return view
end

function UI:CreateStandalone()
  if state.standalone then return state.standalone end
  local frame = CreateFrame("Frame", "MDTPullMarkerConfigFrame", UIParent, "BackdropTemplate"); frame:SetSize(620, 290); applySavedPosition(frame); frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end); frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition(self) end); setBackdrop(frame, COLORS.background)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() frame:Hide() end)
  local content = CreateFrame("Frame", nil, frame); content:SetPoint("TOPLEFT", 4, -4); content:SetPoint("BOTTOMRIGHT", -4, 4); frame.editorView = createEditor(content); frame:Hide(); state.standalone = frame
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, frame:GetName()) end
  return frame
end
function UI:CreateEmbedded(parent) if not parent then return nil, "parent-missing" end if parent.MDTPullMarkerEditorView and parent.MDTPullMarkerEditorView.root then return parent.MDTPullMarkerEditorView.root end local view = createEditor(parent); parent.MDTPullMarkerEditorView = view; return view.root end
function UI:HasViews() return #state.views > 0 end
function UI:Refresh() local model = self:BuildViewModel() for _, view in ipairs(state.views) do refreshView(view, model) end return model end
function UI:Open() local frame = self:CreateStandalone(); frame:Show(); self:Refresh(); return frame end
function UI:Toggle() local frame = self:CreateStandalone(); if frame:IsShown() then frame:Hide() else self:Open() end return frame:IsShown() end
function UI:Close() if state.standalone then state.standalone:Hide() end end
function UI:GetState() return { lastError = state.lastError, open = state.standalone and state.standalone:IsShown() or false } end
function UI:GetLayoutStats() return { viewCount = #state.views, simple = true } end
function UI:OnDisplayChanged() if state.standalone and state.standalone.SetClampedToScreen then state.standalone:SetClampedToScreen(true) end end
