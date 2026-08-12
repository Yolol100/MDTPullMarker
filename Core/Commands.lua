local _, Addon = ...

local Commands = {}
Addon.Commands = Commands

local SMART_MACRO_NAME = Addon.Constants.SmartMacroName
local SECOND_SMART_MACRO_NAME = Addon.Constants.SmartMacroName2

local function chat(message) Addon.Chat(message) end
local function log(level, message, showInChat) Addon.Log(level, message, showInChat) end
local function getGlobal() return Addon.GetGlobal() end

local function getActiveRouteBinding()
  return Addon.MDT and type(Addon.MDT.GetRouteBinding) == "function" and Addon.MDT:GetRouteBinding() or nil
end

local function getRouteBindingCount()
  if not (Addon.MDT and type(Addon.MDT.GetRouteBindings) == "function") then return 0 end
  local count = 0
  for _ in pairs(Addon.MDT:GetRouteBindings() or {}) do count = count + 1 end
  return count
end

local function setBooleanSetting(field, value, label)
  value = tostring(value or ""):lower()
  if value ~= "on" and value ~= "off" then
    chat(("Usage: /mdtpm %s on|off"):format(label))
    return false
  end

  local updated, updateError = Addon.Database.SetGlobal(field, value == "on")
  if not updated then
    log("WARN", label.." could not be saved: "..tostring(updateError), true)
    return false
  end

  log("INFO", label.." set to "..value..".", true)
  return true
end

local function printHelp()
  chat("/mpm - open Pull Marker")
  chat("/mpm map - open MDT markers")
  chat("/mpm bind - bind the route currently selected in MDT")
  chat("/mpm macro [pull][a|b|c] - pick up a prebuilt pull macro, for example /mpm macro 4a")
  chat("/mpm routes - show MDT routes; /mpm unbind - return to legacy current-pull mode")
end

local function printAdvancedHelp()
  chat("Advanced: /mdtpm close | runtimeclose | resetui | next | prev | nextmark | prevmark | complete | reopen")
  chat("Advanced: /mdtpm bind | unbind | routes | macros | route | backend | validate | plan [pull] | safe | doctor | debug on|off | log | clearlog")
  chat("Advanced: /mdtpm autoopen on|off | autoclose on|off | onlymarked on|off")
end

local function printStatus()
  local buildVersion, _, _, interfaceVersion = GetBuildInfo()
  local executor = Addon.MarkerExecutor:GetState()
  local smartStatus = executor.smartMacro or {}

  chat("Version: "..tostring(Addon.Version))
  chat(("Client: %s / interface %s"):format(tostring(buildVersion), tostring(interfaceVersion)))
  chat("Bulk marker mode applies the selected MDT target icons to unmarked mobs (up to 3 per press).")
  local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() == true
  chat("Combat lockdown: "..(inCombat and "active" or "inactive"))
  chat(executor.routeMacroMode
    and "Execution mode: bound MDT route with prebuilt pull macros; max 3 distinct raid icons per macro"
    or "Execution mode: legacy two-macro current-pull mode; max 3 distinct raid icons per macro")
  local binding = getActiveRouteBinding()
  if binding then
    chat(("Bound route: %s; dungeon %s; route macros %s/%s %s; saved dungeon bindings %d"):format(
      tostring(binding.presetName or binding.presetUID or binding.routeKey),
      tostring(binding.dungeonName or binding.dungeonIndex or "unknown"),
      tostring(executor.routeMacros and executor.routeMacros.currentCount or 0),
      tostring(executor.routeMacros and executor.routeMacros.desiredCount or 0),
      executor.routeMacros and executor.routeMacros.executionActive and "active" or "parked",
      getRouteBindingCount()
    ))
  else
    chat(("Bound route for active dungeon: none; saved dungeon bindings %d"):format(getRouteBindingCount()))
  end
  local smartMacros = executor.smartMacros or { smartStatus }
  for index, macroStatus in ipairs(smartMacros) do
    chat(("Smart macro %s: %s%s%s"):format(
      tostring(macroStatus.name or (index == 1 and SMART_MACRO_NAME or SECOND_SMART_MACRO_NAME)),
      macroStatus.conflict and "name conflict" or (macroStatus.exists and (macroStatus.current and "ready" or "outdated") or "missing"),
      macroStatus.location and ("; "..tostring(macroStatus.location)) or "",
      macroStatus.warning and ("; "..tostring(macroStatus.warning)) or ""
    ))
  end
  chat("Direct secure-button keybind: "..tostring(smartStatus.boundKey or "not assigned"))
  chat("Secure refresh queued: "..(executor.pendingSecureRefresh and "yes" or "no"))
  chat("Macro refresh queued: "..(executor.pendingMacroRefresh and "yes" or "no"))
  local ownership = executor.markerOwnership or Addon.MarkerOwnership:GetState()
  if ownership then
    chat(("Marker owner: %s%s"):format(
      tostring(ownership.owner or "none"),
      ownership.electionPending and " (electing)" or (ownership.isOwner and " (this client)" or " (passive client)")
    ))
  end
  chat(executor.routeMacroMode
    and "Pull progression: pressing MPM###A/B/C selects that bound-route pull immediately; chain-pulls do not wait for the previous pull to die"
    or "Pull progression: all required batches -> wait for combat end -> reset marker pool -> next MDT pull")

  local dbState = Addon.Database.GetState()
  if dbState then
    local database = Addon.GetDatabase()
    chat(("Database: %s; schema %s; retired legacy routes %d"):format(
      dbState.persistent and "persistent" or "in-memory",
      tostring(database and database.schemaVersion or "unknown"),
      tonumber(dbState.retiredLegacyRoutes) or 0
    ))
    if dbState.lastError then chat("Database error: "..tostring(dbState.lastError)) end
  end

  local mdtStatus = Addon.MDT:GetStatus()
  if mdtStatus then
    chat(("MDT: %s / %s / %s"):format(
      tostring(mdtStatus.version or "unknown-version"),
      tostring(mdtStatus.mode),
      tostring(mdtStatus.compatibility)
    ))
    if mdtStatus.fingerprint then chat("Route fingerprint: "..mdtStatus.fingerprint) end
  end

  local cooperation = Addon.MDTFocusMarkerBridge:Refresh()
  if cooperation then
    chat(("Focus Marker cooperation: %s - %s"):format(tostring(cooperation.status), tostring(cooperation.message)))
  end

end

local function printBackendStatus()
  -- Compatibility command: backend and MDT now share the same route state.
  Addon.MDT:PrintStatus()
end

local function printValidation()
  local valid, findings = Addon.MDT:ValidateActiveRoute()
  local summary = Addon.Validator.Summarize(findings)
  chat(("Active route validation: %s; %d errors; %d warnings"):format(
    valid and "valid" or "invalid",
    summary.errors,
    summary.warnings
  ))
  for index = 1, math.min(10, #findings) do
    local finding = findings[index]
    chat(("%s: %s at %s"):format(tostring(finding.severity), tostring(finding.code), tostring(finding.path)))
  end
end

local function printMarkerPlan(argument)
  local pullIndex = Addon.DataUtils.PositiveInteger(argument)
  local plan, findings = Addon.MDT:BuildMarkerPlan()
  if not plan then
    local first = type(findings) == "table" and findings[1] or nil
    if type(first) == "table" then
      chat(("Marker plan failed: %s at %s"):format(
        tostring(first.code or first.severity or "unknown-error"),
        tostring(first.path or "unknown")
      ))
      for index = 2, math.min(10, #findings) do
        local item = findings[index]
        if type(item) == "table" then
          chat(("%s: %s at %s"):format(tostring(item.severity), tostring(item.code), tostring(item.path)))
        end
      end
    else
      chat("Marker plan failed: "..tostring(findings or "unknown-error"))
    end
    return
  end

  local summary = plan.summary
  chat(("Marker plan: %s; %d pulls; %d assignments; %d errors; %d warnings"):format(
    tostring(plan.status),
    summary.markedPulls,
    summary.assignments,
    summary.errors,
    summary.warnings
  ))

  if pullIndex then
    local pull = Addon.MarkerPlanner.GetPull(plan, pullIndex)
    if not pull then
      chat("Pull not found in marker plan: "..tostring(pullIndex))
      return
    end
    chat(("Pull %d: %d assignments"):format(pull.index, #pull.assignments))
    for _, assignment in ipairs(pull.assignments) do
      chat(("P%d M%d enemy %d clone %d%s"):format(
        assignment.priority,
        assignment.marker,
        assignment.enemyIndex,
        assignment.cloneIndex,
        assignment.name and " - "..assignment.name or ""
      ))
    end
  end

  for index = 1, math.min(10, #(findings or {})) do
    local item = findings[index]
    chat(("%s: %s at %s"):format(tostring(item.severity), tostring(item.code), tostring(item.path)))
  end
end

local function printTestInstructions()
  chat("1. MDT is authoritative: Skull stays Skull, Cross stays Cross; duplicate use of one icon inside a pull blocks instead of remapping.")
  chat("2. Select your intended route in MDT and use /mpm bind outside combat. The addon prebuilds MPM001A, MPM002A, and B macros where needed.")
  chat("3. Pull the pack and press that pull's macro. If a B macro exists, wait about 4 seconds before pressing it.")
  chat("4. Unique mob names are targeted automatically with /targetexact and marked with set-if-unmarked ~N.")
  chat("5. A marked mob name repeated anywhere else in the bound MDT route is parked as manual-required; the addon never guesses which physical clone you meant.")
  chat("6. When multiple clients are present, one leased marker owner (tank -> leader -> DPS -> healer) remains authoritative.")
end


local function printDoctor()
  local executor = Addon.MarkerExecutor:GetState()
  local runtime = Addon.RuntimeController and Addon.RuntimeController:GetState() or {}
  local session = Addon.DungeonSession and Addon.DungeonSession:GetState() or {}
  local smart = executor.smartMacro or {}
  local smartMacros = executor.smartMacros or { smart }
  local instruction = executor.currentInstruction or runtime.assignment

  chat(("Doctor: dungeon active=%s; route match=%s; combat=%s"):format(
    tostring(session.active == true), tostring(session.routeMatches), tostring(type(InCombatLockdown) == "function" and InCombatLockdown() and "yes" or "no")
  ))
  chat(("Doctor: plan=%s; pull=%s/%s; instruction=%s/%s; gate=%s"):format(
    tostring(runtime.planStatus or runtime.status or "unknown"),
    tostring(runtime.currentPullPosition or 0), tostring(runtime.pullCount or 0),
    tostring(runtime.instructionPosition or 0), tostring(runtime.instructionCount or 0),
    tostring(executor.currentInstructionError or "ready")
  ))
  local owner = executor.markerOwnership or {}
  chat(("Doctor: marker owner=%s; local-owner=%s; election-pending=%s; peers=%s; legacy=%s; lease=%ss/%ss; progression=%s"):format(
    tostring(owner.owner or "none"), tostring(owner.isOwner == true), tostring(owner.electionPending == true),
    tostring(owner.peerCount or 0), tostring(owner.legacyPeerCount or 0), tostring(owner.heartbeatSeconds or "?"),
    tostring(owner.peerTTLSeconds or "?"), tostring(executor.progressionMode or "unknown")
  ))
  local death = executor.pullDeathTracking or runtime.deathTracking
  if death then
    chat(("Doctor: death tracking=%s; observed=%s/%s; readable=%s; restricted=%s; reason=%s"):format(
      tostring(death.status or "unknown"), tostring(death.observedTotal or 0), tostring(death.expectedTotal or 0),
      tostring(death.readableDeathEvents or 0), tostring(death.restrictedDeathEvents or 0), tostring(death.lastReason or "none")
    ))
  end
  local batch = executor.currentBatch or {}
  if #batch > 0 then
    local labels = {}
    for _, item in ipairs(batch) do
      labels[#labels + 1] = ("M%s %s"):format(tostring(item.marker or "?"), tostring(item.targetName or "?"))
    end
    chat("Doctor: bulk batch="..table.concat(labels, " | "))
  elseif instruction then
    chat(("Doctor: next marker=%s; mob=%s; assignment=%s"):format(
      tostring(instruction.marker or "?"), tostring(instruction.targetName or instruction.name or "?"),
      tostring(instruction.assignmentID or instruction.id or "?")
    ))
  end
  for _, macroStatus in ipairs(smartMacros) do
    chat(("Doctor: %s exists=%s; current=%s; managed=%s; conflict=%s; location=%s; duplicates=%s; warning=%s; error=%s"):format(
      tostring(macroStatus.name or "macro"), tostring(macroStatus.exists == true), tostring(macroStatus.current == true),
      tostring(macroStatus.managed == true), tostring(macroStatus.conflict == true), tostring(macroStatus.location or "none"),
      tostring(macroStatus.duplicateCount or 0), tostring(macroStatus.warning or "none"), tostring(macroStatus.error or "none")
    ))
    if macroStatus.body then chat("Doctor "..tostring(macroStatus.name or "macro")..": "..tostring(macroStatus.body):gsub("\n", " | ")) end
  end
  local routeMacros = executor.routeMacros or {}
  chat(("Doctor: route-bound=%s; route-macros=%s/%s current; missing=%s; conflicts=%s; parked=%s; stale-active=%s"):format(
    tostring(executor.routeMacroMode == true), tostring(routeMacros.currentCount or 0), tostring(routeMacros.desiredCount or 0),
    tostring(routeMacros.missingCount or 0), tostring(routeMacros.conflictCount or 0),
    tostring(routeMacros.parkedCount or 0), tostring(routeMacros.staleActiveCount or 0)
  ))
  local last = executor.lastMarkerConfirmation
  if last then chat(("Doctor last marker: status=%s; code=%s; marker=%s"):format(tostring(last.status), tostring(last.code or "none"), tostring(last.marker or "?"))) end
end

local function printRecentLogs()
  local logs = type(getGlobal().logs) == "table" and getGlobal().logs or {}
  if #logs == 0 then
    chat("No diagnostic entries stored.")
    return
  end
  local first = math.max(1, #logs - 9)
  for index = first, #logs do
    local entry = logs[index]
    chat(("%s [%s] %s"):format(tostring(entry.time), tostring(entry.level), tostring(entry.message)))
  end
end

function Commands:OpenPrimaryInterface()
  local opened = Addon.MDTIntegration:OpenSection()
  if opened then return true, "mdt" end
  Addon.ConfigurationUI:Open()
  return true, "standalone"
end

local function runRuntimeCommand(label, action)
  -- In bound-route mode every pull macro is already prebuilt, so selecting a
  -- different pull during combat is safe. Legacy mode still relies on rewriting
  -- MDTPM1/MDTPM2 and therefore remains blocked by combat lockdown.
  local routeBound = getActiveRouteBinding() ~= nil
  if not routeBound and type(InCombatLockdown) == "function" and InCombatLockdown() then
    chat(tostring(label).." not executed during combat. Wait until combat ends so the marker macros can refresh safely.")
    return nil, "combat-lockdown"
  end
  local result, runtimeError = action()
  if not result and runtimeError then chat(tostring(label).." not executed: "..tostring(runtimeError)) end
  if Addon.RuntimeFrame:IsOpen() then Addon.RuntimeFrame:Refresh() end
  return result, runtimeError
end

local function syncMacroExecutionState()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return nil, "combat-lockdown" end
  local routeBound = getActiveRouteBinding() ~= nil
  if not routeBound then
    local session = Addon.DungeonSession:Refresh("macro-command-preflight", false)
    if not session or session.active ~= true then return nil, "outside-dungeon" end
  end

  -- /mpm macro is an explicit user action. Refresh the current MDT preset first so
  -- the macro cannot be generated from a stale marker plan after route edits.
  local snapshot, snapshotError = Addon.MDT:Refresh("macro-command", { allowUILoad = true })
  if not snapshot then return nil, snapshotError or "route-data-unavailable" end

  local runtime, runtimeError = Addon.RuntimeController:Refresh("macro-command", true)
  if not runtime then return nil, runtimeError or "runtime-refresh-failed" end
  Addon.DungeonSession:Refresh("macro-command", false)
  return true
end

local function bindCurrentRoute()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    chat("Leave combat first to bind an MDT route.")
    return nil, "combat-lockdown"
  end
  local binding, bindError = Addon.MDT:BindCurrentRoute()
  if not binding then
    chat("Route was not bound: "..tostring(bindError or "route unavailable"))
    return nil, bindError
  end
  local runtime, runtimeError = Addon.RuntimeController:Refresh("route-bound", true)
  if not runtime then
    chat("Route was bound, but its marker plan is not ready: "..tostring(runtimeError))
    return nil, runtimeError
  end
  local macros, macroError = Addon.MarkerExecutor:RefreshRouteMacros("route-bound")
  if not macros then
    chat("Route is bound, but its macros could not be prepared: "..tostring(macroError))
    return nil, macroError
  end
  chat(("Bound MDT route: %s. Prepared %d pull macro(s)."):format(
    tostring(binding.presetName or binding.presetUID or binding.routeKey), #macros
  ))
  return true
end

local function unbindRoute()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    chat("Leave combat first to unbind the route.")
    return nil, "combat-lockdown"
  end
  local cleared, clearError = Addon.MDT:ClearRouteBinding()
  if not cleared then
    chat("Route binding was not cleared: "..tostring(clearError))
    return nil, clearError
  end
  local remainingBindings = getRouteBindingCount()
  local cleaned, cleanupError
  if remainingBindings > 0 then
    cleaned, cleanupError = Addon.MarkerExecutor:ParkRouteMacros("route-unbound-other-dungeons-remain")
  else
    cleaned, cleanupError = Addon.MarkerExecutor:RetireRouteMacros("route-unbound-last-binding")
  end
  Addon.RuntimeController:Refresh("route-unbound", true)
  Addon.MarkerExecutor:OnInstructionChanged("route-unbound")
  if not cleaned and cleanupError ~= "delete-macro-unavailable" and cleanupError ~= "edit-macro-unavailable" then
    chat("Route was unbound, but managed route macro cleanup failed: "..tostring(cleanupError))
  elseif remainingBindings > 0 then
    chat(("Route binding cleared. %d other dungeon binding(s) remain; route macros were parked safely."):format(remainingBindings))
  else
    chat("Route binding cleared. Legacy current-pull macro mode is active again.")
  end
  return true
end

local function printRoutes()
  local routes, routeError = Addon.MDT:ListRoutes({ allowUILoad = true })
  if not routes then
    chat("MDT routes unavailable: "..tostring(routeError))
    return
  end
  if #routes == 0 then
    chat("No MDT routes found for the selected dungeon.")
    return
  end
  for _, route in ipairs(routes) do
    local flags = {}
    if route.current then flags[#flags + 1] = "selected" end
    if route.bound then flags[#flags + 1] = "bound" end
    chat(("Route %d: %s; %d pulls%s"):format(
      route.presetIndex, tostring(route.presetName), tonumber(route.pullCount) or 0,
      #flags > 0 and (" ["..table.concat(flags, ", ").."]") or ""
    ))
  end
end

local function handleSlashCommandUnsafe(rawInput)
  rawInput = tostring(rawInput or ""):match("^%s*(.-)%s*$")
  local command, argument = rawInput:match("^(%S+)%s*(.-)$")
  command = command and command:lower() or "open"
  argument = argument or ""

  if command == "help" then
    printHelp()
  elseif command == "advanced" then
    printAdvancedHelp()
  elseif command == "markarm" then
    Addon.MarkerExecutor:ArmDirectTarget(argument, "actionbar-macro")
  elseif command == "markdone" then
    Addon.MarkerExecutor:ConfirmDirectTarget(argument, "legacy-actionbar-macro")
  elseif command == "a" then
    Addon.MarkerExecutor:ValidateBulkAnchors(argument, "actionbar-bulk-anchor")
  elseif command == "v" then
    Addon.MarkerExecutor:ValidateBulkStep(argument, "actionbar-bulk-step")
  elseif command == "b" then
    Addon.MarkerExecutor:ConfirmBulk(argument, "actionbar-bulk-macro")
  elseif command == "bind" then
    bindCurrentRoute()
  elseif command == "unbind" then
    unbindRoute()
  elseif command == "routes" then
    printRoutes()
  elseif command == "macros" then
    local synced, syncError = syncMacroExecutionState()
    if not synced then
      chat("Route macros are not ready: "..tostring(syncError or "route unavailable")..".")
    elseif not getActiveRouteBinding() then
      chat("No MDT route is bound. Select a route in MDT and use /mpm bind first.")
    else
      local results, macroError = Addon.MarkerExecutor:RefreshRouteMacros("slash-route-macros")
      if results then
        chat(("Prepared %d route macro(s)."):format(#results))
      else
        chat("Route macros are not ready: "..tostring(macroError or "unknown error")..".")
      end
    end
  elseif command == "macro" then
    local synced, syncError = syncMacroExecutionState()
    if not synced then
      if syncError == "combat-lockdown" then
        chat("Leave combat first to place or update macros.")
      elseif syncError == "outside-dungeon" then
        -- Normal idle state: macros activate automatically after entering a dungeon.
      else
        chat("Macros are not ready: "..tostring(syncError or "route unavailable")..". Use /mpm doctor for details.")
      end
    else
      local binding = getActiveRouteBinding()
      if binding then
        local runtime = Addon.RuntimeController:GetState()
        local pullText, batchText = tostring(argument or ""):lower():match("^(%d+)%s*([abc]?)$")
        local pullIndex = tonumber(pullText) or tonumber(runtime.currentPullIndex)
        local batchIndex = batchText == "c" and 3 or (batchText == "b" and 2 or 1)
        local descriptor, descriptorError = Addon.RuntimeController:GetRouteMacroDescriptor(pullIndex, batchIndex)
        if not descriptor then
          chat(("No route macro for pull %s%s: %s"):format(tostring(pullIndex or "?"), ({ "A", "B", "C" })[batchIndex] or "A", tostring(descriptorError)))
        else
          local results, macroError = Addon.MarkerExecutor:EnsureRouteMacros(pullIndex, batchIndex)
          if results then
            chat(descriptor.name.." picked up. Place it on your action bar.")
          else
            chat("Route macro is not ready: "..tostring(macroError or "unknown error")..".")
          end
        end
      else
        local pickupIndex = tonumber(argument) == 2 and 2 or 1
        local results, macroError = Addon.MarkerExecutor:EnsureSmartMacros(pickupIndex)
        if results then
          local picked = results[pickupIndex] or {}
          local pickupState = ""
          if picked.warning == "bulk-second-batch-empty" then
            pickupState = " (idle: this pull has 3 or fewer marked targets)"
          elseif picked.warning == "bulk-second-batch-fewer-than-three-targets" or picked.warning == "bulk-fewer-than-three-targets" then
            pickupState = " (contains fewer than 3 targets)"
          end
          chat((pickupIndex == 2 and "MDTPM2" or "MDTPM1").." picked up"..pickupState..". Place it on your action bar.")
        else
          chat("Macros are not ready: "..tostring(macroError or "unknown error")..". Use /mpm doctor for details.")
        end
      end
    end
  elseif command == "run" or command == "runtime" then
    Addon.RuntimeFrame:Open()
  elseif command == "test" or command == "testinfo" then
    printTestInstructions()
  elseif command == "map" then
    local opened, openError = Addon.MDTIntegration and Addon.MDTIntegration:OpenMap()
    if not opened then chat("MDT map unavailable: "..tostring(openError)) end
  elseif command == "focus" then
    local opened, openError = Addon.MDTIntegration and Addon.MDTIntegration:OpenFocusMarkers()
    if not opened then chat("MDT Focus Marker unavailable: "..tostring(openError)) end
  elseif command == "cooperation" then
    if Addon.MDTFocusMarkerBridge then
      Addon.MDTFocusMarkerBridge:PrintStatus()
    else
      chat("Cooperation check unavailable.")
    end
  elseif command == "safe" then
    local applied, applyError = Addon.MDTFocusMarkerBridge and Addon.MDTFocusMarkerBridge:ApplySafeDefaults()
    if applied then
      if applied.applyWarnings and #applied.applyWarnings > 0 then
        chat("Safe settings saved. Open MDT Focus Marker and change the marker once, or use /reload, to refresh the active Focus Marker action.")
      else
        chat("Safe marker defaults applied. Verify that route and focus icons do not overlap.")
      end
    else
      chat("Safe marker defaults were not applied: "..tostring(applyError))
    end
  elseif command == "runtimeclose" then
    Addon.RuntimeFrame:Close()
  elseif command == "resetui" then
    local reset, resetError = Addon.Database.ResetUIPositions()
    if reset then
      Addon.ConfigurationUI:Close()
      Addon.RuntimeFrame:Close()
      chat("Saved window positions were cleared. Reopen the windows.")
    else
      chat("Window positions could not be cleared: "..tostring(resetError))
    end
  elseif command == "next" then
    runRuntimeCommand("Next pull", function() return Addon.RuntimeController:NextPull() end)
  elseif command == "prev" then
    runRuntimeCommand("Previous pull", function() return Addon.RuntimeController:PreviousPull() end)
  elseif command == "nextmark" then
    runRuntimeCommand("Next marker", function() return Addon.RuntimeController:NextInstruction() end)
  elseif command == "prevmark" then
    runRuntimeCommand("Previous marker", function() return Addon.RuntimeController:PreviousInstruction() end)
  elseif command == "complete" then
    runRuntimeCommand("Complete pull", function() return Addon.RuntimeController:CompleteCurrentPull(true) end)
  elseif command == "reopen" then
    runRuntimeCommand("Reopen pull", function() return Addon.RuntimeController:ReopenCurrentPull() end)
  elseif command == "mdtui" or command == "mdt" or command == "open" then
    local opened, openError = Commands:OpenPrimaryInterface()
    if not opened then chat("Interface unavailable: "..tostring(openError)) end
  elseif command == "standalone" then
    Addon.ConfigurationUI:Toggle()
  elseif command == "close" then
    Addon.ConfigurationUI:Close()
  elseif command == "status" then
    printStatus()
  elseif command == "doctor" then
    printDoctor()
  elseif command == "mdtstatus" then
    Addon.MDT:Refresh("slash-command")
    Addon.MDT:PrintStatus()
  elseif command == "route" then
    Addon.MDT:Refresh("route-command")
    Addon.MDT:PrintRouteSummary()
  elseif command == "backend" then
    Addon.MDT:SyncActiveRoute()
    printBackendStatus()
  elseif command == "validate" then
    printValidation()
  elseif command == "plan" then
    printMarkerPlan(argument)
  elseif command == "preserve" then
    chat("Bulk markers use set-if-unmarked (~N) for retry safety. Exact MDT marker choices are never remapped; same-name pulls fail closed instead of guessing a physical clone.")
  elseif command == "autoopen" then
    setBooleanSetting("autoOpenRuntime", argument, "autoopen")
  elseif command == "autoclose" then
    setBooleanSetting("autoCloseRuntime", argument, "autoclose")
  elseif command == "onlymarked" then
    setBooleanSetting("openOnlyWithMarkers", argument, "onlymarked")
  elseif command == "mismatch" then
    chat("Route mismatch blocking is always enabled. A mismatched or unverified MDT route is never executable.")
  elseif command == "debug" then
    setBooleanSetting("debug", argument, "debug")
  elseif command == "log" then
    printRecentLogs()
  elseif command == "clearlog" then
    local cleared, clearError = Addon.Database.ClearLogs()
    if cleared then
      chat("Diagnostic entries cleared.")
    else
      chat("Could not clear logs: "..tostring(clearError))
    end
  else
    chat("Unknown command: "..command)
    printHelp()
  end
end

function Commands:HandleSlashCommand(rawInput)
  local _, commandError = Addon.ErrorHandler.Run("slash-command", handleSlashCommandUnsafe, rawInput)
  if commandError and commandError.code then chat("Command failed. Use /mpm doctor for details.") end
end

SLASH_MDTPULLMARKER1 = "/mpm"
SLASH_MDTPULLMARKER2 = "/mdtpm"
SLASH_MDTPULLMARKER3 = "/mdtpullmarker"
SlashCmdList.MDTPULLMARKER = function(input) Commands:HandleSlashCommand(input) end

function Addon.GetState()
  local executor = Addon.MarkerExecutor:GetState()
  local mdt = Addon.MDT:GetStatus()
  return {
    version = Addon.Version,
    preserveExistingMarkers = getGlobal().preserveExistingMarkers,
    executor = executor,
    smartMacro = executor.smartMacro,
    smartMacros = executor.smartMacros,
    keybindCommand = executor.keybindCommand,
    secureClickType = executor.secureClickType,
    pendingSecureRefresh = executor.pendingSecureRefresh,
    pendingMacroRefresh = executor.pendingMacroRefresh,
    pendingMarkerConfirmation = executor.pendingMarkerConfirmation,
    lastMarkerConfirmation = executor.lastMarkerConfirmation,
    pendingPullAdvance = executor.pendingPullAdvance,
    progressionMode = executor.progressionMode,
    markerOwnership = executor.markerOwnership or Addon.MarkerOwnership:GetState(),
    creatureNames = Addon.CreatureNameResolver:GetState(),
    database = Addon.Database.GetState(),
    backend = mdt, -- compatibility alias
    mdt = mdt,
    cooperation = Addon.MDTFocusMarkerBridge:GetStatus(),
    session = Addon.DungeonSession:GetState(),
  }
end

function MDTPullMarker_Open(_, buttonName)
  if buttonName == "RightButton" then
    Addon.RuntimeFrame:Open()
  else
    Commands:OpenPrimaryInterface()
  end
end

function MDTPullMarker_CompartmentEnter(button)
  if not GameTooltip or not button then return end
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText("MDT Pull Marker", 1, 0.82, 0)
  GameTooltip:AddLine("Left-click: open MDT Pull Markers", 1, 1, 1)
  GameTooltip:AddLine("Right-click: open dungeon helper", 0.72, 0.72, 0.72)
  GameTooltip:Show()
end

function MDTPullMarker_CompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
