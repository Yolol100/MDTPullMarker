# MDT Pull Marker live Retail acceptance matrix

This matrix is the manual acceptance gate for a release that claims live Retail support. CI can prove source, packaging, static policy and deterministic behavior, but it cannot prove protected-action, taint, live Mythic+, MDT UI, name-resolution or real group behavior inside the WoW client.

A release may be marked **PASS-CI** when repository validation is green. It may be marked **PASS-LIVE** only after the applicable checks below are performed on the exact packaged build and the evidence is recorded with client build, interface number, addon version and Mythic Dungeon Tools version.

## 1. Installation and dependency contract

- Install the generated archive under `Interface/AddOns/MDTPullMarker/` and confirm the TOC is at `MDTPullMarker/MDTPullMarker.toc`.
- Test with the current supported Retail client for every interface value declared in the TOC.
- Confirm Mythic Dungeon Tools is installed and enabled. MDTPullMarker must not present a false ready state when the required dependency is missing, disabled or incompatible.
- Login, `/reload`, logout/login and character switch must complete without Lua errors.
- Verify saved settings survive reload/logout and an invalid or migrated SavedVariables payload fails safely rather than corrupting the active route state.

## 2. MDT integration and route identity

Test the current supported MDT release and the current upstream development layout when that layout is listed as source-verified in `COMPATIBILITY.md`.

- Open MDT through the addon and verify the supported public API path is preferred.
- Select a route, bind it out of combat and confirm dungeon identity, preset UID/fingerprint and route snapshot match the selected MDT route.
- Edit the selected route after binding. Execution must park or fail closed until the binding is refreshed; stale route data must never be executed as though it were current.
- Switch to another preset with similar pulls. Ambiguous UID/fingerprint matching must fail closed rather than guessing.
- Exercise MDT load-on-demand/UI loading, `/reload` with a bound route and reopening MDT after the addon is already initialized.
- Verify missing/renamed upstream API surfaces produce a clear incompatible/degraded status rather than a Lua error.

## 3. Dungeon and Mythic+ session gating

- Outside a dungeon, automatic execution must remain parked.
- Enter the correct dungeon and verify the active challenge map/dungeon identity agrees with the bound route before execution becomes available.
- Enter a different dungeon with a saved binding for another map. The addon must not execute that route.
- Start a Mythic+ challenge and verify the route/owner state is frozen at the intended boundary.
- Complete, reset and leave the challenge. Verify session state is rebuilt cleanly and no stale owner, pull or macro state survives into the next run.
- Test zoning/reconnect/reload around `CHALLENGE_MODE_START`, reset and completion events.

## 4. Group ownership and addon messaging

The ownership protocol is allowed to coordinate before an active challenge. During the challenge/chat-messaging lockdown it must not depend on live addon-message exchange.

- Solo: local client becomes the marker owner without waiting for peers.
- Group with one addon user: that client becomes owner and remains stable.
- Group with multiple compatible addon users: election converges to exactly one owner after the settle window and heartbeats do not create visible chat spam.
- Mixed current/legacy protocol: current clients must stay passive when compatibility cannot be established safely.
- Leader/role changes before challenge: ownership may re-elect and converge.
- Challenge start: ownership freezes; no mid-run peer expiry or roster churn may silently elect a different owner.
- Simulate owner disconnect/leave after challenge start. The addon must fail closed/passive rather than inventing a new authoritative owner from incomplete communication.
- Verify `C_ChatInfo.InChatMessagingLockdown()` or an unavailable/erroring messaging API suspends sends without throwing.

## 5. Secure marking and macro contract

- All protected marking actions must remain user initiated. No code path may cast, target, focus or mark protected units automatically from runtime combat data.
- Verify secure button/macro attributes are prepared out of combat and are never mutated while `InCombatLockdown()` is active.
- Test one-, two- and three-target batches. No activation may attempt more than three distinct target-marker operations.
- Verify the macro begins with the combat guard and only uses the expected `/targetexact`, `/tm [harm,nodead] ~N` and `/cleartarget` forms.
- Test target names containing spaces, apostrophes, non-ASCII characters and supported locale text.
- Test malicious/invalid target names containing control characters, brackets, semicolons or excessive length. They must be rejected rather than inserted into a macro.
- Test duplicate/ambiguous creature names. Automatic exact-name execution must be parked/manual when the physical clone cannot be proven.
- Verify macro length stays within the client limit and an oversized plan fails closed.
- Press repeated marker batches faster and slower than the marker window; throttling must never exceed the supported marker-operation cap.

## 6. Pull progression and death evidence

- Legacy/current-pull mode: execute every required batch, enter combat, end combat and verify progression advances exactly once.
- Bound-route macro mode: selecting a later pull macro must select that pull directly without depending on the previous pull's death completion.
- Verify `UNIT_DIED` evidence advances only when the expected pull can be proven complete.
- Feed/read a secret or unreadable GUID case in live conditions when available. The tracker must enter restricted/ambiguous state and must not guess an NPC ID or complete a pull from that event.
- Chain-pull two packs and verify deaths from the earlier pack cannot incorrectly complete the later pull.
- Wipe/reset and re-engage; stale death evidence must not carry into the new attempt.

## 7. Marker ownership and existing raid markers

- Pre-mark one or more mobs manually before execution. `~N` set-if-unmarked behavior must preserve already marked units as intended.
- Verify duplicate use of one raid icon inside the same pull is rejected by route validation rather than silently remapped.
- Confirm Skull/Cross/etc. remain the exact marker numbers authored in MDT.
- Trigger `RAID_TARGET_UPDATE` while the addon is active and verify confirmation/ownership state stays coherent.

## 8. UI, keybind and recovery behavior

- Open/close the configuration UI and runtime frame at default UI scale and at representative small/large UI scales.
- Change resolution/UI scale while the frame is open; layout must remain accessible and on-screen.
- Create, delete, rename or duplicate the managed macros and trigger `UPDATE_MACROS`; the addon must detect conflicts and avoid overwriting unrelated user macros.
- Change the secure keybind and trigger `UPDATE_BINDINGS`; displayed state and secure execution must remain consistent.
- `/reload` during a parked, ready and post-combat state; the addon must recover without executing stale state.

## 9. Taint, errors and performance

Run with Lua errors enabled and, when practical, taint logging enabled.

- No blocked-action or taint error may originate from MDTPullMarker during configuration, challenge start, combat, marking, wipe or challenge completion.
- No repeating Lua errors during unavailable/secret API conditions.
- No unbounded table/log/macro growth across at least 20 representative pulls or repeated route refreshes.
- No excessive addon-message traffic before challenge and no dependency on messaging during active challenge lockdown.
- No noticeable frame-time spikes from route refresh, name resolution, marker confirmation or UI updates.

## 10. Release evidence

Record at minimum:

- MDTPullMarker version and packaged ZIP SHA-256.
- WoW client build/interface.
- MDT version/commit or release.
- Test character/region and dungeon used.
- Group composition/addon-version mix for ownership tests.
- PASS/FAIL for every applicable section, with notes for intentionally untestable cases.
- Any Lua/taint logs or screenshots needed to explain a failure.

Do not promote an RC/beta to stable merely because CI is green or upstream source was reviewed. Live client evidence is a separate release gate.
