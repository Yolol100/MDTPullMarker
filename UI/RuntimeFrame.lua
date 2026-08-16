local _, Addon = ...

local L = Addon.L or {}

local RuntimeFrame = {}
Addon.RuntimeFrame = RuntimeFrame

local frame
local COLORS = { background = { 0.0588, 0.0588, 0.0588, 0.985 }, border = { 1, 1, 1, 0.10 }, gold = { 1, 0.8196, 0, 1 } }

local function joinNumbers(values) local result = {} for _, value in ipairs(values or {}) do result[#result + 1] = tostring(value) end return table.concat(result, ", ") end
local function currentRouteMacroNames(runtime)
  local names = {}
  if not (Addon.RuntimeController and type(Addon.RuntimeController.GetRouteMacroDescriptor) == "function") then return names end
  for batchIndex = 1, 3 do local descriptor = Addon.RuntimeController:GetRouteMacroDescriptor(runtime.currentPullIndex, batchIndex) if descriptor and descriptor.name then names[#names + 1] = descriptor.name end end
  return names
end
local function setBackdrop(target)
  if not target or not target.SetBackdrop then return end
  target:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  target:SetBackdropColor(unpack(COLORS.background)); target:SetBackdropBorderColor(unpack(COLORS.border))
end
local function makeText(parent, template) return parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal") end
local function applySavedPosition(target)
  target:ClearAllPoints(); local position = Addon.Database.GetUIPosition("runtime")
  if position then target:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y) else target:SetPoint("CENTER", UIParent, "CENTER", 0, 130) end
end
local function savePosition(target)
  if not target.GetPoint then return end
  local point, _, relativePoint, x, y = target:GetPoint(1)
  if point and relativePoint then Addon.Database.SaveUIPosition("runtime", { point = point, relativePoint = relativePoint, x = x or 0, y = y or 0 }) end
end
local function ensureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "MDTPullMarkerRuntimeFrame", UIParent, "BackdropTemplate")
  frame:SetSize(430, 190); applySavedPosition(frame); frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton"); frame:SetScript("OnDragStart", function(self) self:StartMoving() end); frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition(self) end); setBackdrop(frame)
  frame.title = makeText(frame, "GameFontNormalLarge"); frame.title:SetPoint("TOPLEFT", 14, -14); frame.title:SetTextColor(unpack(COLORS.gold))
  frame.route = makeText(frame, "GameFontHighlightSmall"); frame.route:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10); frame.route:SetPoint("RIGHT", -14, 0); frame.route:SetJustifyH("LEFT")
  frame.macros = makeText(frame, "GameFontHighlight"); frame.macros:SetPoint("TOPLEFT", frame.route, "BOTTOMLEFT", 0, -12); frame.macros:SetPoint("RIGHT", -14, 0); frame.macros:SetJustifyH("LEFT")
  frame.help = makeText(frame, "GameFontNormal"); frame.help:SetPoint("TOPLEFT", frame.macros, "BOTTOMLEFT", 0, -16); frame.help:SetPoint("RIGHT", -14, 0); frame.help:SetJustifyH("LEFT")
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() frame:Hide() end)
  frame:Hide(); if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, frame:GetName()) end
  return frame
end

function RuntimeFrame:Refresh()
  ensureFrame()
  local runtime = Addon.RuntimeController:GetState(); local session = Addon.DungeonSession:GetState(); local executor = Addon.MarkerExecutor:GetState()
  local macro1 = executor.smartMacros and executor.smartMacros[1] or executor.smartMacro or {}; local macro2 = executor.smartMacros and executor.smartMacros[2] or {}
  local macroConflict = macro1.conflict == true or macro2.conflict == true; local boundMode = executor.routeMacroMode == true; local routeMacros = executor.routeMacros or {}
  local routeMacroConflict = tonumber(routeMacros.conflictCount) and tonumber(routeMacros.conflictCount) > 0; local currentNames = boundMode and currentRouteMacroNames(runtime) or {}
  frame.title:SetText(("Pull %s of %s"):format(tostring(runtime.currentPullPosition or 0), tostring(runtime.pullCount or 0)))
  if session.active and session.routeMatches == true then frame.route:SetText(tostring(session.challengeName or session.instanceName or runtime.dungeonName or "Dungeon").." • route ready")
  elseif session.active then frame.route:SetText(("|cffffad33"..(L.OPEN_MATCHING_ROUTE or "Open the matching MDT route").."|r")) else frame.route:SetText(tostring(runtime.presetName or "MDT route").." • waiting for dungeon") end
  local ownership = executor.markerOwnership or {}
  if runtime.planStatus == "blocked" then frame.macros:SetText(("|cffff5959"..(L.MARKED_PULL_NEEDS_ATTENTION or "Marked pull needs attention in MDT").."|r"))
  elseif runtime.automaticTargeting == false then frame.macros:SetText(("|cffffad33"..(L.SAME_NAME_PARKED or "Same-name pull parked safely").."|r"))
  elseif ownership.electionPending then frame.macros:SetText(("|cffffad33"..(L.ELECTING_OWNER or "Electing party marker owner...").."|r"))
  elseif ownership.owner and ownership.isOwner == false then frame.macros:SetText("|cff8fa3b8"..tostring(ownership.owner).." is applying party markers|r")
  elseif boundMode and routeMacroConflict then frame.macros:SetText("|cffff5959MPM route macro name conflict|r")
  elseif boundMode and routeMacros.current == true and routeMacros.executionActive == true then frame.macros:SetText(("|cff59df80Route macros ready: %s|r"):format(#currentNames > 0 and table.concat(currentNames, " + ") or "no markers for this pull"))
  elseif boundMode and routeMacros.current == true then frame.macros:SetText("|cffffad33Route macros are ready but inactive for this dungeon|r")
  elseif boundMode and type(InCombatLockdown) == "function" and InCombatLockdown() then frame.macros:SetText(("|cffffad33"..(L.ROUTE_MACROS_REFRESH_AFTER_COMBAT or "Route macros refresh after combat").."|r"))
  elseif boundMode then frame.macros:SetText(("|cffffad33Preparing route macros %s/%s...|r"):format(tostring(routeMacros.currentCount or 0), tostring(routeMacros.desiredCount or 0)))
  elseif macroConflict then frame.macros:SetText("|cffff5959MDTPM macro name conflict|r")
  elseif macro1.current and macro2.current then frame.macros:SetText("|cff59df80MDTPM1 + MDTPM2 ready|r")
  elseif type(InCombatLockdown) == "function" and InCombatLockdown() then frame.macros:SetText(("|cffffad33"..(L.MACROS_UPDATE_AFTER_COMBAT or "Macros update after combat").."|r")) else frame.macros:SetText(("|cffffad33"..(L.PREPARING_MACROS or "Preparing macros...").."|r")) end

  local submission = executor.bulkSubmission; local flowText
  if boundMode then
    if #currentNames == 0 then flowText = "This MDT pull has no safe automatic marker macro." else flowText = table.concat(currentNames, "  ->  wait ~4 sec  ->  ") end
    if submission and submission.allRequired then flowText = "Current pull markers applied • tracking remains active until combat ends" end
  else
    flowText = submission and submission.batch2Required and "MDTPM1  ->  wait ~4 sec  ->  MDTPM2" or "MDTPM1"
    if submission and submission.allRequired then flowText = "Markers applied • next marked pull loads after combat"
    elseif submission and submission.batch1 and submission.batch2Required then flowText = "Marker macro 1 applied  ->  wait ~4 sec  ->  marker macro 2"
    elseif submission and submission.batch1 and not submission.batch2Required then flowText = "MDTPM1 submitted • next marked pull loads after combat" end
  end
  local targetingText = runtime and runtime.automaticTargeting == false and Addon.Constants.AutomaticTargetingWarning or nil
  if targetingText then frame.help:SetText(targetingText)
  elseif boundMode and routeMacroConflict then frame.help:SetText("Rename/delete the unrelated MPM###A/B/C macro. Pull Marker never overwrites a personal macro.")
  elseif not boundMode and macroConflict then frame.help:SetText("Rename/delete the unrelated MDTPM1 or MDTPM2 macro. Pull Marker will never overwrite an unrecognized macro.")
  elseif ownership.owner and ownership.isOwner == false then frame.help:SetText("Pull Marker stays inactive here to prevent duplicate markers.")
  elseif boundMode and executor.pendingPullAdvances and #executor.pendingPullAdvances > 0 then
    local pending = {}; for _, item in ipairs(executor.pendingPullAdvances) do pending[#pending + 1] = item.pullIndex end
    local skipped = runtime.skippedPulls and #runtime.skippedPulls > 0 and (" • skipped: "..joinNumbers(runtime.skippedPulls)) or ""
    frame.help:SetText("Active/submitted pulls: "..joinNumbers(pending)..skipped.." • final progress resolves at a safe combat boundary.")
  elseif executor.pendingPullAdvance then frame.help:SetText("Markers applied - waiting for combat to end before loading the next MDT pull.") else frame.help:SetText(flowText) end
  return runtime
end

function RuntimeFrame:Open() Addon.RuntimeController:Refresh("runtime-frame-open") ensureFrame():Show() self:Refresh() return frame end
function RuntimeFrame:Close() if frame then frame:Hide() end end
function RuntimeFrame:IsOpen() return frame and frame:IsShown() or false end
function RuntimeFrame:GetLayoutStats() return { width = 430, height = 190, simple = true } end
function RuntimeFrame:OnDisplayChanged() if frame and frame.SetClampedToScreen then frame:SetClampedToScreen(true) end end
