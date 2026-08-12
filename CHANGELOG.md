# Changelog

## 1.0.0-rc54 — bounded creature-name cache + completion hardening

- Bounded the non-English localized creature-name resolver cache to 4,096 entries with deterministic FIFO eviction. Long sessions that encounter many unique NPC IDs can no longer grow this runtime cache without limit; evicted names are safely resolved again on demand.
- Added regression coverage that resolves 10,000 unique NPC IDs across multiple FIFO wraparounds, proves the cache remains capped, proves the oldest entry is evicted and re-resolved, proves recent cached entries remain reusable, and verifies `Clear()` resets the bounded-cache state.
- Re-ran the extended completion checks for asynchronous stale callbacks, event storms, dependency absence/late load, UI/frame refresh stress, SavedVariables failure cases, planner stress, package parity and two stable release rounds.
- No route identity/fingerprint logic, target strategy, marker indices, A/B/C macro format, three-marker limit, 255-byte limit, owner election, combat-owner freeze, chain/skip/overlap/death semantics, SavedVariables schema or user setting was intentionally changed.

## 1.0.0-rc53 — route callback fail-closed preflight hardening

- Fixed a bound-route callback ordering defect where a valid `MPM###A/B/C` token could switch the logical pull and activate death tracking before the current dungeon/route/owner gate was revalidated. Rejected callbacks now leave pull, skip/engagement and death-context state unchanged.
- Added target-pull completion preflight so a callback for an already completed pull is rejected before that pull can be re-engaged or its death context reactivated.
- Added regressions for passive-owner, route-mismatch and completed-pull callbacks, including assertions that rejected callbacks perform no pull/death-state mutation.
- Synchronized the regression-suite README release heading with the actual package version and added a package-integrity assertion so stale release labels fail the suite.
- No marker indices, target strategy, macro naming/body format, A/B/C limits, three-marker-per-macro rule, 255-byte limit, route identity/fingerprint algorithm, owner-election priority, overlap/death semantics, SavedVariables schema or user setting was intentionally changed.

## 1.0.0-rc52 — owner-proof + UID-less route convergence hardening

- Updated grouped owner communication for the current Retail `C_ChatInfo` result-code API: `RegisterAddonMessagePrefix` and `SendAddonMessage` now accept only a proven success result (`0` on current Retail, with legacy boolean `true` retained for compatibility). Throttle, lockdown, invalid, secret/opaque and other non-success results fail closed.
- Hardened roster proof so unreadable/malformed role, leader or local alive/dead state cannot be coerced into a valid owner election.
- Closed the remaining delayed-peer split-brain class. In grouped play, every client now derives the same deterministic roster anchor using the existing priority order (tank, leader, DPS, healer, stable name). Peer silence can no longer promote a different lower-priority client. If that anchor is not an eligible addon participant while still present in the roster, the group intentionally has no active marker owner until the roster makes another member the deterministic anchor.
- Kept combat-owner immutability intact: an unproven combat remains passive, while a proven deterministic owner cannot be replaced mid-combat by heartbeat/roster timing.
- Hardened UID-less route recovery. The resolver now searches the complete preset set for the saved membership fingerprint before using unique-name edit continuity, so preset reordering cannot let a different same-name route steal the binding.
- Added explicit duplicate-fingerprint handling without changing the existing route fingerprint algorithm. If multiple UID-less presets share the same membership fingerprint, the saved preset name may distinguish them only when exactly one matching candidate has that name; otherwise resolution fails closed with `bound-route-fingerprint-ambiguous` instead of selecting marker assignments arbitrarily.
- Added regressions for current enum-style addon-message returns, non-success/secret send results, unreadable role/leader/death state, isolated simultaneous clients, deterministic anchor recovery, UID-less preset reorder, duplicate fingerprint name tie-break and duplicate-fingerprint ambiguity.
- Re-ran the normal 2,000-case planner fuzz gate plus an independent 5,000-case planner stress seed and a 2,000-roster party/raid owner stress with no peer delivery.
- No macro naming/body format, A/B/C batch limit, three-marker-per-macro rule, 255-byte limit, targeting strategy, marker indices, chain/skip/overlap/death semantics, SavedVariables schema or user setting was changed.

## 1.0.0-rc51 — combat owner-election race hardening

- Fixed a pre-combat election race where combat could begin during the 0.8-second owner settle window and freeze a tentative local owner before peers were discovered. A combat that starts without a proven settled group owner now freezes a passive owner state for that entire combat.
- Added an explicit combat-freeze flag so `nil` is a real frozen owner result. This prevents a client that entered combat without a proven owner from acquiring ownership later in the same combat after delayed roster/peer information arrives.
- Prevented peer heartbeats from refreshing `MarkerExecutor` while the combat owner is frozen. Underlying peer state may still prepare the next election, but it can no longer cancel an in-flight marker confirmation for the current combat.
- Prevented settle-timer completion and group-loss/unknown-group settle paths from refreshing the executor during a frozen combat. This closes the same marker-confirmation cancellation race for `GROUP_ROSTER_UPDATE`/world-change timing.
- Added regressions for combat beginning before election settle, late peer arrival during a passive combat freeze, peer eligibility changes during a proven combat freeze, settle callbacks during combat, and group loss during combat.
- No route binding, marker assignment, macro body/name, A/B/C pacing, chain-pull/skip/overlap semantics, SavedVariables schema or user setting was changed.

## 1.0.0-rc50 — fail-closed macro ownership + group election hardening

- Removed the hard-coded `120` fallback for the account/character macro-space boundary. Macro enumeration and mutation now require a readable, non-secret, positive integer `MAX_ACCOUNT_MACROS`; otherwise macro management stops before create/edit/delete.
- Hardened `GetNumMacros()` handling: non-numeric, negative, fractional, secret or impossible account counts are no longer treated as an empty macro space. Ownership/slot arithmetic fails closed with an explicit error.
- Hardened multiplayer marker ownership. Grouped clients now remain passive when addon-prefix registration is not positively confirmed, when the election send call throws, when group/raid state cannot be read, or when the roster cannot be completely resolved. Solo execution remains independent of group communication.
- Kept combat owner freeze intact: a previously proven owner is not opportunistically replaced mid-combat, while pre-combat/group-state uncertainty cannot elect a local fallback owner.
- Added regressions for missing/secret macro boundaries, invalid macro counts, unavailable communication, send exceptions, unreadable group counts, incomplete rosters, unknown raid state and unknown group state.
- Strengthened the static policy so a numeric `MAX_ACCOUNT_MACROS` fallback cannot be silently reintroduced.
- Hardened source/test packaging to exclude nested Python cache artifacts and assert they are absent from the built source archive. Runtime/CurseForge package contents are unchanged by this cleanup.
- No route semantics, marker assignments, A/B/C batching, macro names/bodies, chain-pull/skip/overlap behavior, SavedVariables schema or user settings were intentionally changed.

## 1.0.0-rc49 — future-season locale continuity hardening

- Fixed a future-season route-binding edge case where a route bound before its Challenge Map ID existed could become unresolvable after the player changed client locale before the season started. Missing-map-ID recovery now compares the active challenge dungeon against MDT's **current** localized dungeon name for the saved MDT dungeon index, with the persisted bind-time name only as fallback.
- Bound snapshots now refresh their dungeon display identity from the current MDT locale when safely available, preventing stale pre-locale-change dungeon names from leaking into session/UI route matching.
- Kept the recovery path fail-closed: bindings that already carry a different Challenge Map ID are never repurposed, ambiguous current-name matches are rejected, and the MDT UI is never force-loaded during combat.
- Expanded the eight-dungeon Midnight Season 2 regression fixture to simulate a client-locale change between pre-season binding and season activation; all eight routes must still resolve to the same saved MDT dungeon/preset without hardcoded production dungeon tables.
- Stress-ran the marker planner over 5,000 randomized cases in addition to the normal 2,000-case release fuzz gate; no new planner invariant failures were found.
- No marker semantics, macro names, batch sizes, owner election, overlap/skip behavior, SavedVariables schema or user settings were changed.

## 1.0.0-rc48 — Midnight Season 2 route-identity hardening

- Hardened future-season route selection: a route bound before `C_ChallengeMode.GetMapTable()` exposes its dungeon can now be recovered when that dungeon later becomes the active Mythic+ map, using only a unique client-localized dungeon-name match and never another MDT dropdown selection.
- When binding inside an active key, a missing route `challengeMapID` may be filled from the live Challenge Map ID only when the active and MDT dungeon names normalize to the same identity; mismatches still fail closed.
- Active-dungeon `/mpm unbind` and route-status lookup use the same future-season recovery path, so a pre-season binding remains controllable after the season begins.
- Added an eight-dungeon Midnight Season 2 compatibility fixture using the current MDT 6.2.1 dungeon indexes and Challenge Map IDs for Murder Row, Den of Nalorakk, The Blinding Vale, Voidscar Arena, Altar of Fangs, Ruby Life Pools, Temple of Sethraliss and King's Rest. Production code remains data-driven and contains no Season 2 dungeon table.
- Expanded the MDT 6.2.x compatibility fixture to exercise the current load-on-demand `MDTDungeonEnemyMixin:SetUp(data, clone)` capture path through NPC ID, exact target name and a ready marker plan.
- No marker semantics, batch sizes, macro names, owner election, chain-pull behavior, SavedVariables schema or user settings were changed.

## 1.0.0-rc47 — release hardening + 2026 audit cleanup

- Retired two historical SavedVariables (`runtimeLocked` and `warnRouteMismatch`) through schema 12; neither setting controlled a current runtime path, and route/dungeon matching remains a hard fail-closed invariant.
- Removed unreferenced private helpers and legacy internal wrappers after source-wide reference checks; the rc42 compatibility alias `Addon.Backend = Addon.MDT` remains intentionally preserved.
- Hardened macro ownership: if account and character macro spaces cannot both be enumerated reliably, reserved-name management now fails closed instead of trusting a single name lookup.
- Hardened marker-owner communications so only known `H`/`R`/`B` protocol messages received through PARTY or RAID may affect peer election.
- Unified duplicate-name automatic-targeting guidance so configuration and runtime UI report the same route-wide safety rule.
- Added an executable CurseForge archive preflight to the release build: the exact runtime ZIP is checked for one versionless root folder, exact case-sensitive `MDTPullMarker/MDTPullMarker.toc`, safe paths and conservative archive hygiene before unpack/retest.
- Removed engineering-only `tests`, `scripts` and `LIVE_TEST_CHECKLIST.md` from the runtime ZIP while retaining them in the source+tests archive.
- Reordered TOC interface metadata to put current Retail `120100` first while retaining `120007` compatibility. No marker, route, macro, chain-pull, owner-election or UI feature behavior was intentionally changed.

## 1.0.0-rc46 — per-dungeon routes + overlap-safe progression

- Migrated route binding storage to schema 11 with one chosen MDT route per dungeon while preserving the existing rc45 binding automatically.
- Made the active Mythic+ challenge-map identity authoritative: another dungeon's saved binding is never used as a fallback, and active-dungeon bind/unbind operations fail closed on mismatches.
- Added overlap-aware marked-pull state. Multiple chain-pulled marked packs can stay engaged/pending simultaneously, forward jumps track untouched marked pulls as skipped, and returning to a skipped pull re-engages it.
- Reworked death evidence into independent active-pull contexts. Unique readable deaths can progress overlapping pulls independently; an NPC death that could belong to multiple active pulls is explicitly ambiguous and never guessed.
- Expanded same-name safety from current/adjacent pulls to the complete bound route so skipping an intermediate pull cannot make a non-adjacent `/targetexact` clone ambiguity unsafe.
- Preserved action-bar macro identity across dungeon/route changes: no-longer-needed managed `MPM###A/B/C` macros are parked at the safe idle body instead of deleted, and are reactivated at the same macro index when needed again.
- Changed descriptor-set failure handling to park independently proven route macros first; deletion remains only an emergency fallback if an active managed body cannot be made inert. Personal same-name macros remain untouched.
- Updated runtime/doctor diagnostics and live-test coverage for per-dungeon bindings, parked macro counts, overlap/skips, route-wide duplicate names and stable action-bar slots.

## 1.0.0-rc45 — bound-route precompute + chain-pull macros

- Added explicit MDT route binding. A bound preset stays authoritative even when the visible MDT route dropdown later moves to another preset; `/mpm bind`, `/mpm unbind`, `/mpm routes` and `/mpm macros` expose the workflow.
- Added full-route precomputation through `Core/RouteMacroPlan.lua`. Safe automatic pulls receive deterministic `MPM###A/B/C` macros whose numbers match the original MDT pull indexes.
- Extended bound-route execution from the legacy six-marker/two-macro ceiling to all eight raid icons across at most three batches, while preserving the three-marker-per-macro and exact 255-byte limits. Legacy unbound mode intentionally remains a two-macro/six-marker fallback.
- Made chain-pulling a first-class execution path: pressing a later prebuilt pull macro switches runtime directly to that pull even while the previous pull is still alive, without rewriting a protected macro during combat.
- Added execution-context parking for the entire prebuilt route set. Route macros become executable only in the matching dungeon, before challenge completion and on the elected marker-owner client; otherwise their stable action-bar names contain the safe idle body.
- Added transactional descriptor-set macro management. Personal `MPM###A/B/C` collisions are preserved and fail closed, partial create/edit failures retire proven managed route macros, and stale managed macros are removed when a route edit reduces the set.
- Added route-binding persistence/migration. UID-backed MDT routes resolve strictly by UID; UID-less copied presets use a bounded unique-name/preferred-slot fallback that survives normal pull/marker edits instead of silently following the visible dropdown.
- Added adjacent-pull same-name chain safety. A target name duplicated inside the same pull or immediately neighboring pull becomes `manual-required`; non-adjacent duplicates remain eligible for automatic exact-name execution.
- Generalized planner/runtime submission state to A/B/C, including deterministic three-batch packing, four-second local pacing between batches and direct token-to-pull resolution.
- Added separate route-bound compatibility coverage for MDT 6.1.20 and 6.2.x, plus database binding tests, route-macro planning/execution tests, parking tests, stale cleanup, personal collision preservation, partial-create rollback and 2,000 randomized two-/three-batch planner cases.

## 1.0.0-rc44 — modular macro lifecycle + dual MDT compatibility

- Extracted protected macro discovery, ownership proof, creation, edit verification, collision handling, pickup, status and combat deferral into `Runtime/SmartMacroManager.lua`, reducing `MarkerExecutor.lua` by more than 300 lines without changing the execution contract.
- Made the two reserved names transactional as a pair: a personal collision on either `MDTPM1` or `MDTPM2` is detected before the other macro is edited or created.
- Removed the hard-coded character macro-capacity assumption from creation fallback. Account storage is preferred; when unavailable/full, the protected `CreateMacro(..., true)` call is authoritative for character storage.
- Added regressions for cross-name transaction safety, unexpected account-macro creation failure, full account+character slot exhaustion, and character-capacity-independent fallback.
- Added a dedicated MDT 6.1.20 compatibility mock for the monolithic legacy object alongside the existing MDT 6.2.x core/UI load-on-demand compatibility test. Both preserve dungeon identity, route shape and native per-clone marker assignments.
- Expanded the TOC/full-load contract to require `SmartMacroManager` and kept the full existing macro, planner, owner, localization and runtime regression suite green after the refactor.
- Added reproducible release packaging so the distributable ZIP is built only after the regression suite passes and is then unpacked and revalidated.
- Hardened pair-level failure handling: if either reserved macro cannot be proven/refreshed/created safely, every independently proven addon-managed `MDTPM1`/`MDTPM2` copy is retired so no stale peer remains executable; unrelated personal same-name macros are preserved.
- Added exact-name readback verification after `EditMacro`; body/icon matches no longer hide an unexpected macro-name mutation.
- Added fail-closed tests for partial pair creation, peer refresh failure, no-op deletion, secret/restricted macro counts or metadata, secret create returns, and unexpected create/edit names.
- Added UTF-8/multibyte byte-budget regressions so the planner and runtime agree on the actual 255-byte macro limit, not character count.
- Added a static release policy test that blocks dynamic code execution, direct targeting/raid-marker APIs, `OnUpdate` loops, macro mutation outside `SmartMacroManager`, hard-coded character-slot capacity dependencies, and unsafe TOC ordering.
- Added `LIVE_TEST_CHECKLIST.md` so the only remaining client-only verification has an explicit reproducible matrix instead of an undocumented manual step.

## 1.0.0-rc43 — fail-closed macro ownership + testable macro core

- Added an out-of-combat guard as the first line of every active `MDTPM1`/`MDTPM2` body. Accidental presses before combat now stop before `/cleartarget`, `/targetexact` or `/tm` can run.
- Compacted the signed batch token to a 12-character batch+64-bit-hash form while retaining the stricter `[harm,nodead]` protected marker guard.
- Made the planner call the same `Core/MarkerMacro.lua` builder as the runtime, so macro-length acceptance and execution can no longer drift. The planner now searches the tiny two-macro partition space and rebalances long exact names across `MDTPM1`/`MDTPM2` when that keeps both bodies within 255 bytes.
- Extracted token parsing, target-name sanitization, macro-body construction and legacy-body recognition into `Core/MarkerMacro.lua` so the protected command surface can be regression-tested without loading the full runtime.
- Hardened reserved-name ownership: an existing `MDTPM1`/`MDTPM2` is editable only when both its body and dedicated icon identify it as addon-managed. Unrecognized same-name macros now fail closed with an explicit conflict instead of being overwritten.
- Made duplicate-name refresh transactional: every same-name macro is ownership-checked before any copy is edited.
- New macros now prefer account-wide macro slots and use character slots only as fallback; existing managed macros stay in their current slot.
- Added macro location/conflict/duplicate diagnostics to `/mpm doctor` and explicit UI guidance for resolving a reserved-name collision.
- Added executable regression coverage for the macro builder, adaptive planner limits, 2,000 randomized planner cases, owner election/combat freeze, ownership conflicts, account-first creation, current MDT 6.2.x core/UI load-on-demand compatibility, TOC integrity, full TOC load and Lua syntax.
- Refreshes the local player identity during owner recomputation so a transiently unavailable name at very early startup cannot become a permanent election fallback.
- Revalidated the architecture against current MDT Focus Marker, MPlusMarker and AutoMarkAssist patterns while retaining the safer MDT-route-authoritative, user-activated secure-macro model required by current Retail restrictions.

## 1.0.0-rc42

- Simplified the addon without changing its execution model or safety boundaries.
- Removed the duplicate `Services/Backend.lua` state layer. MDT route reading and marker-plan building now use one `Addon.MDT` state; `Addon.Backend` remains as a compatibility alias only.
- Reduced the top-level code structure to four clear areas: `Core`, `Integrations`, `Runtime`, and `UI`. Single-file `Models`/`Planning` folders were folded into `Core`, and MDT UI integration moved under `Integrations`.
- Removed redundant defensive checks around mandatory internal modules. WoW/MDT external APIs remain guarded and fail closed where required.
- Removed duplicate backend/MDT diagnostics while keeping the legacy `/mpm backend` command as an alias to the same route status.
- Kept all rc41 marker behavior: exact MDT markers, same-name fail-closed handling, combat-safe macro updates, 3+3 batching, owner heartbeat/lease, NPC localization, death-aware pull progression, wipe recovery, and rc40 compatibility.

## 1.0.0-rc41

- Fixed the rc40 owner-TTL bug by adding a 5-second owner heartbeat with an 18-second peer lease; silent peers now expire instead of allowing stale/double ownership.
- Added mixed rc40 compatibility pings so rc40 clients renew their lease through their existing `H`/`R` protocol even though rc40 has no periodic heartbeat.
- Changed deterministic owner priority to tank -> group leader -> DPS -> healer -> stable name order, while keeping the elected owner frozen through combat.
- Added pull death tracking from readable current-pull `UNIT_DIED` / `UNIT_DESTROYED` events. Partial evidence blocks premature progression; complete evidence confirms the safe boundary; secret/restricted identity falls back safely.
- Reset death evidence on every new combat attempt so a wipe/retry cannot inherit deaths from the previous attempt.
- Expanded same-name safety to include unmarked clones and client-localized names resolved from NPC IDs.
- Updated diagnostics and active UI/help text for owner leases and death-aware safe-boundary progression.

## 1.0.0-rc40

- Added party marker-owner election between rc40 clients. Leader wins when eligible, then tank, then stable name order; passive clients park their managed macros and the owner is frozen through combat.
- Added NPC-ID based client-local creature-name resolution using `C_TooltipInfo.GetHyperlink`, with secret-string and malformed-name rejection. Non-English routes can now execute when every marked target resolves safely; unresolved names remain fail-closed.
- Added an explicit pending pull-advance state. All required batches arm the current pull index + route fingerprint, and combat-end advancement is rejected if that context changed.
- Clarified chain-pull behavior: dynamic protected macro bodies are never swapped during uninterrupted combat; the next MDT pull loads at the next safe combat boundary.
- Removed current rc38-era help/status text about marker remapping and target+mouseover duplicate-name handling. Same-name pulls remain `manual-required` and no `/targetenemy` guessing is used.
- Updated runtime UI and `/mpm doctor` with marker-owner and combat-boundary progression state.

## 1.0.0-rc39

- Reworked execution around a pull-scoped marker pool: MDT remains authoritative, submitted marker state is tracked per pull, and Skull/Cross/etc. are reset/reused when the next marked pull becomes active.
- Adopted the MPlusMarker-style combat-safe macro lifecycle: reserved macros are updated in place, changes are queued during combat, and missing macros are created only in a live dungeon session.
- Removed all marker remapping. Reusing the same raid-target icon twice in one pull now blocks instead of silently changing MDT's assignment.
- Removed the rc38 target/mouseover duplicate-name workaround from the automatic path. Same-name marked pulls now fail closed as `manual-required`; rc39 never uses unfiltered `/targetenemy` cycling that could mark an unrelated mob.
- Added a live `IsInInstance()` gate to macro creation/execution so stale cached dungeon state cannot create missing macros after the player has already left the instance.
- Kept automatic pull advancement after combat when all required batches were submitted and the player is alive; wipe recovery stays on the same pull.
- Updated the compact UI to distinguish automatic pulls from same-name pulls that cannot be safely resolved under current Retail restrictions.

## 1.0.0-rc38

- Preserves the exact MDT marker for repeated mob names; Cross/X is no longer remapped just because another marked clone has the same visible name.
- Replaces ineffective repeated `/targetexact` attempts for same-name clones with explicit `@target` + `@mouseover` anchors when both copies share a batch, or `@mouseover` when the primary was already handled.
- Updates macro ownership recognition, macro-length validation, help text, and runtime status for mixed exact-name/target/mouseover batches.
- Keeps automatic exact-name marking for unique mob names and continues to avoid unsafe unfiltered `/targetenemy` cycling.


## 1.0.0-rc37

- Reserved `MDTPM1` and `MDTPM2` as addon-owned macro names and overwrite existing/legacy bodies in place instead of reporting a name conflict.
- Synchronize duplicate reserved-name macros so stale action-bar copies cannot keep an old combat-blocking body.
- Do not create missing marker macros at login/outside dungeons; create and populate them when the dungeon session becomes active.
- Keep existing reserved macros in a safe idle state outside dungeons so action-bar placement can persist without executing a stale route.
- Re-enable automatic dungeon runtime activation for existing rc36 databases through schema 9.
- Suppress outside-dungeon macro errors and hide/disable pickup actions until a dungeon is active.
- Replaced unsupported arrow glyphs in the helper text with ASCII arrows for reliable WoW-font rendering.

## 1.0.0-rc36 — scenario-audited operator-state hardening

- Fixed the configuration UI so an available MDT route no longer implies a ready marker plan when backend plan construction fails; the UI now reports the plan as unavailable and points to `/mpm doctor`.
- Fixed `/mpm macro` combat feedback: combat lockdown is now reported as a combat restriction instead of incorrectly telling the user to open a different MDT route.
- Re-ran the expanded release matrix across route normalization, planner boundaries, macro ownership/collisions, slot exhaustion, stale tokens, combat ordering, throttle handling, wipe recovery, challenge completion, corrupt SavedVariables, and current MDT 6.2.1 data-shape compatibility.

## 1.0.0-rc35 — audited retry-safe 3+3 execution

- Follow-up audit: `/mpm plan` now prints the actual first planner finding instead of a Lua table address when plan construction fails.
- Fixed macro-pickup feedback so an idle/partial `MDTPM2` is reported accurately instead of always being presented as a populated macro.
- The configuration UI now refreshes the active MDT route and runtime plan before picking up `MDTPM1`/`MDTPM2`, matching the stale-route protection already used by `/mpm macro`.
- Final audit cleanup: guarded the status command when `InCombatLockdown` is unavailable in partial/mock environments, corrected stale README text to match the current `[harm,nodead]` macro guard, and removed duplicate changelog headings.
- Corrected the target-state guard after online macro verification: bulk execution is `/cleartarget` → `/targetexact <name>` → `/tm [harm,nodead] ~N`. The later secure-command condition evaluates the then-current target, preventing a same-named friendly or dead unit from being marked. The batch-token schema was bumped so older signed macros cannot be accepted as current.
- Hardened route snapshots: normalization and bounded copying now support the same capped 20,000-enemy/20,000-clone surface, public snapshots correctly inherit top-level per-clone `enemyAssignments`, sparse list-form snapshots no longer lose valid later enemies, and backend snapshot-copy failures transition fail-closed to `route-error` instead of silently storing `nil`.
- Revalidated Blizzard's `/tm ~N` semantics and now use set-if-unmarked for every bulk marker. This makes repeated or partially throttled presses idempotent: a marker that already landed is not toggled off or overwritten on retry.
- Replaced the weak first-assignment/count batch token with a 16-hex fingerprint over the route, complete target list, markers, execution modes, and exact-vs-set-if-unmarked policy. Stale macros now fail closed even when pull index and assignment count happen to match.
- Added `UPDATE_MACROS` self-healing outside combat so deleted/stale managed `MDTPM1` and `MDTPM2` macros are recreated/refreshed without manual commands.
- Advanced pull/instruction navigation commands now fail closed during combat, because changing the runtime cursor while secure macro bodies are locked would leave an old action-bar macro active until combat ended.
- Bulk submissions now count only while combat lockdown is active. An accidental out-of-combat `MDTPM1`/`MDTPM2` press may still place a protected marker, but it cannot advance pull progress later.
- A wipe no longer advances the route: when combat ends while the player is dead/ghost, submitted batch state is cleared and the same pull requires fresh macro presses after recovery.
- Kept the hard 3-marker-per-macro cap and the local 4-second retry window. Blizzard publishes the 3-unit limit but not the exact reset duration. A rejected early press now restarts the full local wait and reports that correctly.
- Same-name extra copies remain best-effort exact-name-only; the addon never uses unfiltered target cycling that could mark a different mob name.
- Updated the missing-global character macro-slot fallback from 18 to the current 30-slot client limit, preventing false `macro-slots-insufficient` failures when Blizzard's slot constant cannot be read.
- Replaced the ambiguous one-line idle macro with a distinctive safe idle body. Legacy `/stopmacro` idle bodies migrate only when their macro icon also matches the addon, reducing the chance of overwriting a personal macro that happens to use a reserved name.
- Fixed duplicate reserved macro-name detection: when Blizzard exposes macro enumeration APIs the addon now enumerates all account/character slots instead of trusting `GetMacroIndexByName`, which only returns the first match. Duplicate `MDTPM1`/`MDTPM2` names now fail closed.
- Strengthened managed-macro ownership: a recognized body is editable only when its icon also matches the addon-managed icon, reducing the chance of touching a personal macro with a reserved name.
- Fixed nil-first Lua iteration edge cases: `GetTime` now remains a real fallback when `GetTimePreciseSec` is absent, second-slot keybindings are still inspected when the first slot is empty, and duplicate helper UI no longer depends on a dense two-item table.

## 1.0.0-rc34 — submission-safe dual macro workflow

- Stopped treating `/mpm b` macro fall-through as proof that every protected `/tm` succeeded. Bulk presses are now tracked as submitted batches, not per-unit confirmations.
- Pull progress no longer advances from the combat macro callback. A marked pull advances only after combat ends and every required batch for that pull was submitted.
- A 4–6 target pull cannot advance if only `MDTPM1` was pressed; a 1–3 target pull can advance after `MDTPM1` alone.
- The four-second local gate now counts every valid-token macro attempt, including rejected/too-early retries, because the protected marker lines execute before the slash callback.
- The last marker-attempt timestamp now survives pull/route state resets so a fast transition cannot accidentally under-estimate the global Blizzard marker window.
- Every generated exact-name lookup now starts with `/cleartarget`; duplicate fallback no longer relies on any assumed `/targetexact` cycling behavior.
- Kept duplicate-name execution fail-safe: exact-name only, primary MDT marker first, later copies get unused `~N` fallbacks, and no unfiltered `/targetenemy` cycling.
- Verified Mythic Dungeon Tools 6.2.1 as a current source-compatible version and kept the existing per-clone `enemyAssignments` integration path.
- Updated the compact UI to distinguish submitted batches from confirmed markers and to show that the next marked pull loads after combat.
- Re-ran syntax, planner fuzz, duplicate-marker, macro-management, throttle/submission, and clean-package regression tests.

## 1.0.0-rc33 — exact MDT primaries + safe duplicate fallback

- Primary and unique mobs now use the exact MDT marker instead of `~N`, so a wrong pre-existing icon is corrected to the route icon.
- Unique/primary mobs used exact MDT markers in that historical build; later same-name fallbacks used `~N`.
- Kept duplicate targeting exact-name-only: no `/targetenemy` or other unfiltered cycling can mark a different mob type.
- For an immediately adjacent same-name fallback in the same macro, the primary target is intentionally retained before the second `/targetexact`; this gives WoW a chance to resolve another exact-name copy while remaining fail-safe if it resolves the primary again.
- Re-ran syntax, planner fuzz, dual-macro, migration, macro-management and clean-package regression tests.

## 1.0.0-rc32 — safe exact-name 3+3 execution

- Removed `/targetenemy` from duplicate-name handling so a fallback marker can never be applied to a different mob name by an unfiltered enemy cycle.
- Same-name extras now receive an unused marker and use exact-name, set-if-unmarked best-effort targeting.
- All bulk `/tm` lines use `~N` plus `[harm,nodead]`, making repeat presses idempotent and preventing overwrite of existing markers.
- Removed per-step combat readback callbacks from the primary bulk path; Midnight may make unit/marker data unavailable or secret during combat.
- Preserved exact route order: MDTPM1 is marked assignments 1-3 and MDTPM2 is 4-6.
- Added planner-side 255-character macro budget validation.
- Forced preserve-existing behavior in schema 8 because safe retries and duplicate fallback depend on set-if-unmarked markers.
- Kept a conservative four-second local gate between the two user presses; Blizzard documents the 3-unit burst limit but not an exact reset time.

## 1.0.0-rc31 — automatic same-name fallback and per-step verification

- Removed the normal target+mouseover requirement for a two-mob identical-name case.
- The first same-name mob keeps its MDT marker; the second is always remapped to a genuinely unused fallback icon.
- The second same-name attempt uses one native `/targetenemy` cycle and `/tm ~N`, so an already-marked candidate is never overwritten.
- Added `/mpm v` after every protected marker action. A correct final marker can no longer falsely confirm earlier failed `/targetexact` steps.
- Final batch confirmation now requires every expected per-step validation record for the exact batch token.
- If the duplicate cycle lands on a different visible name, progress fails closed and the addon reports one short retry warning instead of silently advancing.
- Limited fully automatic same-name handling to two marked copies of one exact name; larger same-name groups block instead of guessing.
- Kept two combat macros, maximum three `/tm` operations each, unique markers across both macros, and the conservative four-second second-batch guard.
- Updated the compact UI and documentation to show free duplicate fallback markers instead of target+hover instructions.

## 1.0.0-rc30 — deterministic 3+3 execution and duplicate-name anchors

- Reads the current MDT per-clone target-marker assignments and preserves each unique MDT icon as the first choice.
- Enforces one effective raid icon per marked mob across the whole pull. Reused MDT icons are remapped deterministically to an unused icon instead of appearing again in `MDTPM2`.
- Plans at most six marked mobs as two explicit batches: `MDTPM1` (max 3) and `MDTPM2` (max 3). More than six blocks fail-closed.
- Keeps both macro bodies prebuilt outside combat and executable after combat starts.
- Replaces unsafe repeated `/targetexact` guessing for identical mob names with live anchors: one identical mob is `@target`, the other is `@mouseover`, and both are marked in the same macro press with different effective icons.
- Validates duplicate anchors when readable: expected name, hostile/alive state, expected marker, and target/mouseover not being the same unit. Failed validation never advances internal pull progress.
- Supports up to four marked copies of the same exact name across the two macros (two live anchors per batch); larger groups block safely.
- Shortened unique-name macro steps to `/cleartarget` → `/targetexact` → `/tm N`, preserving the stale-target safety while improving the 255-byte macro budget.
- Included batch/execution/remap fields in the runtime plan signature so route edits cannot leave a stale execution plan active.
- Kept automatic macro creation idempotent and collision-safe; unrelated user macros named `MDTPM1`/`MDTPM2` are never overwritten.
- Kept the UI compact and added only a short target+hover hint when an identical-name batch requires it.
- Default helper auto-open is now off unless the user explicitly enables it.

## 1.0.0-rc29 — simple UI and automatic macros

- `MDTPM1` and `MDTPM2` are now created automatically outside combat; a missing macro is no longer treated as a refresh warning.
- Removed the noisy `[WARN] macro_missing:MDTPM1` chat loop. Internal diagnostics stay in the log/doctor output.
- Replaced the large configuration screen with a minimal route status, macro status, workflow line, and three buttons.
- Replaced the large dungeon helper with a compact optional status window and disabled automatic opening during migration to rc29.
- Kept the dual combat batches: `MDTPM1` marks targets 1-3 and `MDTPM2` targets 4-6.
- Repeated macro setup remains idempotent and does not recreate existing addon-owned macros.

## 1.0.0-rc28 — dual combat batches and macro collision fix

- Replaced the single managed `MDTPM` macro with `MDTPM1` (targets 1-3) and `MDTPM2` (targets 4-6), both prebuilt before combat.
- `/mpm macro` creates/updates both macros and picks up `MDTPM1`; `/mpm macro 2` picks up `MDTPM2`.
- Fixed the WoW “A macro named ... already exists” failure by resolving `GetMacroIndexByName` before enumeration/creation and rechecking immediately before `CreateMacro`.
- Existing managed `MDTPM1`/`MDTPM2` macros are edited in place; unrelated macros with either name remain fail-closed and are never overwritten.
- The old `MDTPM` macro name is no longer used for new execution, so an rc27/older `MDTPM` can remain without colliding.
- Added a conservative 4-second route-progress guard between successful bulk batches. Blizzard does not publish the exact reset duration; pressing `MDTPM2` too quickly never advances addon progress and must be retried.
- Each individual macro still contains no more than three `/tm` operations, matching Blizzard's current target-marker burst restriction.

## 1.0.0-rc27 — three-target combat bulk marking

- Reworked `MDTPM` around the requested workflow: build the macro before the pull, enter combat, then press it once to target and mark up to three MDT assignments.
- Removed the generated `/stopmacro [combat]` gate. Combat does not inherently block user-triggered `/tm`; Blizzard currently limits target-marker macros to at most three units in a very short time.
- A bulk macro contains at most three `/tm` operations and never attempts a fourth marker in the same press.
- Each target step now runs `/cleartarget` before `/targetexact`, then `/tm [harm,nodead] N`. If an exact-name lookup fails, the marker cannot accidentally be applied to the previous target.
- Bulk mode uses the exact marker numbers from MDT instead of `~N`, so an existing wrong icon on the selected mob is replaced rather than silently preserved.
- Multiple planned targets with the same exact name are blocked fail-closed in bulk mode. `/targetexact` cannot deterministically map identical live units back to separate MDT clone indexes in one press.
- Managed-macro ownership recognition now accepts the rc27 1–3 target bulk body while retaining rc26/rc25 recognition for safe migration.
- Updated diagnostics, test instructions, bindings, runtime labels, and documentation for combat-capable three-target execution.

## 1.0.0-rc26 — marker-result confirmation and diagnostics

- Replaced the rc25 post-`/tm` `markdone` fall-through handshake with a pre-`/tm` assignment arm plus bounded `RAID_TARGET_UPDATE` confirmation.
- Runtime progress no longer advances merely because the macro reached the line after `/tm`; a missing marker update leaves the same instruction active and reports `marker-update-not-observed`.
- Uses `GetRaidTargetIndex` only when its value is readable to verify the expected icon; secret/unavailable readback falls back to the bounded marker-update event.
- Preserved rc25 macro-body recognition only for safe migration; legacy `markdone` never counts as success unless readable marker state matches.
- Added `/mpm doctor` with dungeon/route gate, combat state, current instruction, managed macro ownership/body, and last marker result.
- Marker confirmation validates `RAID_TARGET_UPDATE` synchronously so same-name `@mouseover` instructions cannot race a pointer move on the next frame.
- `/mpm macro` now refreshes the current MDT preset and runtime plan first, preventing a managed macro from being built against stale route-marker state.
- Registered `RAID_TARGET_UPDATE` and cancels stale pending attempts when instructions or combat state change.
- Kept the release intentionally pre-pull/out-of-combat: proximity is not an automatic trigger, and same-name multi-marked mobs still require player mouseover selection plus a physical key press.
- Kept Blizzard burst pacing after three rapidly confirmed marker changes.

## 1.0.0-rc25 — priority marking and same-name multi-marker assist

- Added explicit per-pull marker priority: Skull → Cross → Moon first, followed by Square → Triangle → Diamond → Circle → Star.
- Stopped collapsing multiple marked mobs that share the exact same name in one pull. Those assignments are now retained and sorted by marker priority.
- Added a secure same-name mouseover sequence: hover a different intended same-name mob for each press while the single `MDTPM` action automatically advances through Skull, Cross, Moon, and any lower-priority configured markers.
- Kept automatic `/targetexact` behavior for unique names and the existing first-match behavior when only one marked instruction exists among several same-name live mobs.
- Updated managed-macro ownership recognition for the new mouseover sequence without weakening collision protection.
- Simplified setup wording, made outside-dungeon status visually neutral, surfaced the Skull → Cross → Moon priority in the MDT panel/runtime helper, and clarified when hover is required.
- Added regression coverage for marker priority, three identical names with Skull/Cross/Moon, managed mouseover macro construction, automatic sequence advancement, and unique-name behavior.

## 1.0.0-rc24 — final release certification hardening

- Made route-to-dungeon verification a mandatory execution invariant. The historical `warnRouteMismatch` SavedVariables key is retained only for migration compatibility and can no longer make a mismatched or unverified route executable.
- Fixed an option-precedence bug where an explicit or saved `Preserve existing target markers = off` could be converted to `nil` before planning and therefore behave like preserve mode was still enabled.
- Fixed managed-macro ownership recognition so an `MDTPM` macro containing an extra injected command line can never be mistaken for an addon-owned direct macro and overwritten or retired.
- Fixed run lifecycle progress leakage: entering a new dungeon run, `CHALLENGE_MODE_START`, or `CHALLENGE_MODE_RESET` now clears confirmed assignments and completed pulls before restarting at the first marked route pull.
- Hardened secret/corrupt SavedVariables handling for database roots, schema versions, UI coordinates, logs, and archival backups; these paths now reject or normalize unsafe values without direct conversion/stringification.
- Extended secret-value hardening for MDT numeric metadata, Focus Marker marker values, macro icons, bindings, timing values, and multi-return API wrappers.
- Preserved the explicit duplicate-name first-match policy, mandatory outside-dungeon/completion idle state, stale-macro retirement, conservative marker pacing, and MDT 6.1/6.2 fail-closed metadata behavior.
- Added dedicated adapter, locale/macro, new-run reset, migration/database, randomized planner, full-load, lifecycle, static security, manifest, and final-ZIP verification coverage for the final certification gate.

## 1.0.0-rc23 — runtime state safety and MDT integration hardening

- Fixed a critical ordering bug where route, pull, or instruction changes could refresh the secure button and managed `MDTPM` macro before the new runtime state was installed, leaving the previous mob or pull executable.
- Initial runtime setup, route-unavailable states, pull changes, instruction changes, manual completion, and reopening now refresh execution surfaces only after the authoritative state change.
- Completed pulls force marker execution idle until reopened or advanced.
- Marker execution is fail-closed outside active party dungeons, on route mismatch when that safety gate is enabled, and after Mythic+ completion; session changes immediately rebuild or idle execution surfaces.
- A genuinely changed route resets progress to the first marked pull instead of inheriting an editor-selected pull from the replacement route.
- Changing the route-mismatch safety setting now refreshes execution immediately.
- Extended the version/locale/dungeon-bound MDT 6.2 enemy metadata cache with dungeon name and Challenge Map ID, allowing a valid cached route to recover after `/reload` without unnecessarily loading the MDT UI layer just to re-identify the dungeon.
- Existing rc21/rc22 metadata caches are automatically enriched with dungeon identity the next time MDT UI identity is available, avoiding repeated UI-only enrichment on later reloads.
- Exposed `Preserve existing target markers` in the MDT settings panel and documented that `/tm ~N` deliberately leaves an already-marked target unchanged.
- Added initialization recovery so an unexpected startup exception does not permanently mark a partial initialization as complete; startup can retry on `PLAYER_LOGIN`.
- Hardened multi-return Blizzard/MDT API wrappers so secret secondary return values are scrubbed before comparisons or status processing instead of leaking into normal runtime state.
- Hardened error reporting and stable hashing against secret values, and made the error wrapper preserve exact Lua return tuples including nil-leading, interior-nil, and trailing values.
- Kept marker pacing conservative: Blizzard documents a maximum of three macro target-marker assignments in a very short time but does not publish an exact reset duration.
- Expanded regression coverage for stale secure actions, outside-dungeon gating, route mismatch toggles, Challenge completion, cached dungeon identity, initialization recovery, and randomized route planning.

## 1.0.0-rc22 — English release surface and language consistency

- Converted all user-facing configuration, runtime, slash-command, first-run, tooltip, binding, cooperation, README, compatibility, and changelog text to English.
- Kept internal API names, SavedVariables keys, command tokens, status codes, and MDT contracts unchanged so the language cleanup does not alter runtime behavior or saved-data compatibility.
- Standardized first-match wording, route/macro status labels, failure messages, and in-game testing instructions across the embedded MDT panel and standalone runtime helper.
- Fixed the `/mdtpm test` router so it prints the documented manual test protocol instead of opening the runtime helper; `/mdtpm testinfo` remains an equivalent compatibility alias.
- Re-ran syntax, module-load, route-planner, macro, database, migration, locale, MDT integration, UI smoke, TOC/XML, and package validation after the language conversion.

## 1.0.0-rc21 — MDT 6.2 reload, locale, and data safety

- Added a small version/locale/dungeon-bound enemy metadata cache for the active MDT dungeon only, allowing an MDT 6.2 route to recover NPC IDs, exact target names, and clone counts after `/reload` or a new login without maintaining a second route database.
- During an active dungeon session, silently loads the MDT 6.2 load-on-demand UI outside combat for route identity, even when the preset is already available from SavedVariables.
- Made exact target names locale-safe: English MDT source names are directly verified on `enUS`/`enGB`; a non-English client without a reliable localized MDT name is blocked fail-closed instead of running a potentially incorrect `/targetexact`.
- Legacy MDT continues to use its own `L` table for localized target names.
- Fixed duplicate-name detection so visible names are compared exactly; punctuation differences such as `A-B` and `A B` are no longer incorrectly collapsed.
- Hardened SavedVariables transactions: historical migration backups are no longer recursively copied or re-nested, and damaged/large archival backups do not block the active database.
- Hardened Focus Marker and macro diagnostics against corrupted tables and secret macro/binding values.
- Corrected the rc20 help text and MDT adapter warning for unverified target locales.
- Expanded regression coverage for reload/cache recovery, locale mismatch, punctuation-distinct targets, corrupted backups/settings, secret API values, and MDT 6.2 UI enrichment.
- Corrected runtime wording so the addon no longer claims to have read back a secret raid-target result; the UI now reports executed marker actions and asks for visual in-game icon verification.

## 1.0.0-rc20

- Identically named mobs are no longer blocked outright: per pull, one MDT instruction uses the first exact-name match selected by WoW; additional marked clones with the same name are collapsed and are not marked again.
- The planner reports identical mob names as warnings instead of blockers; duplicate marker icons inside the same pull remain blocking conflicts.
- The direct macro supports the first-match policy while preserving hostile/dead/combat guards and marker-burst pacing.
- Removed a duplicate `rateDelayRemaining()` declaration from `MarkerExecutor:OnInstructionChanged()`.
- Synchronized the internal addon version, TOC, and documentation to rc20.
- Refined the configuration and runtime UI with MDT-style colors, a clearer status badge, a subtle accent line, more compact setup actions, and explicit first-match wording.

## 1.0.0-rc19 — direct exact-name single-press marker candidate

- Replaced the rc18 two-step mouseover/GUID flow with one physical action: `/targetexact <MDT mob name>`, followed by the planned `/tm` marker and an assignment-bound final macro line.
- Removed the runtime dependency on secret hostile UnitGUID/NPC ID values, so Midnight secret unit identity no longer blocks the direct macro flow.
- Removed `GetRaidTargetIndex` from runtime confirmation because this readback can be secret inside Midnight instances; the final macro line is now the non-secret completion handshake.
- After three rapid different marker assignments, holds the next target macro until the end of a conservative four-second window to respect Blizzard's >3-unit target-marker burst restriction.
- On MDT 6.2, captures the full clone table supplied by MDT from a single map blip for that mob type, making off-route identical clones visible to name-ambiguity logic.
- Initially blocked marked target names that occurred multiple times in the active route or available dungeon-wide MDT metadata because `/targetexact` cannot enforce a specific MDT clone index. This policy was later replaced by the explicit first-match behavior in rc20.
- Preserved the additional blocker for marked identical NPC clones inside the same pull at that stage of development.
- Sanitized MDT target names against macro command/conditional injection and blocked unsafe or missing names fail-closed.
- Made `MDTPM` clear the old target, target the planned exact name, stop on missing/friendly/dead targets, and only then execute the marker.
- Refreshed the macro and secure keybind after each safely handled assignment; an outdated addon-owned macro is withdrawn when possible if a required edit fails.
- Removed the old arm/confirm state, `UPDATE_MOUSEOVER_UNIT` listener, and remaining rc18 two-step production logic.
- Fixed `/mpm run`, which opened the runtime window twice.
- Clarified that hover-only behavior without a click/key cannot execute a protected raid marker; only one press is required and no preliminary hover is needed.
- Preserved the same route/session logic for Normal, Heroic, Mythic, and Mythic+.
- Expanded regression coverage for exact-name macro construction, stale assignment tokens, secret marker readback, route/dungeon name ambiguity, macro injection, marker-burst pacing, macro-update rollback, and all four dungeon modes.

## 1.0.0-rc18 — fail-closed verify-then-mark release candidate

- Replaced the one-step marker action with a two-step workflow: first physical action verifies, second physical action marks.
- Blocked wrong or unmarked NPCs before `/tm` was prepared.
- Bound the second step to the same UnitGUID, route fingerprint, pull, and assignment, with a four-second expiry.
- Cancelled an armed marker when mouseover, pull, instruction, or marker-plan state changed.
- Blocked marker execution in combat to prevent stale secure actions from applying to another mob.
- Turned missing NPC identity and marked identical NPC clones inside the same pull into hard planner errors.
- Added temporary, non-persistent MDT 6.2 enemy metadata capture through MDT's own `MDTDungeonEnemyMixin:SetUp` path.
- Debounced MDT metadata refreshes and never wrote back to MDT.
- Classified MDT 6.1.20 and 6.2.0-alpha5 as exact source-checked contracts and removed an unsupported local-verification claim.
- Explicitly tracked Normal, Heroic, Mythic, and Mythic+ difficulty status without hardcoded dungeon lists.
- Updated UI, help text, binding label, and documentation for the new safe workflow.
- Expanded regression coverage for wrong NPC, GUID changes, timeout, combat, preserve-existing, route mismatch, difficulty modes, randomized routes, and MDT 6.2 capture.
- Detected the Midnight `C_Secrets.ShouldUnitIdentityBeSecret("mouseover")` restriction before GUID/NPC processing and blocked the marker action with `unit-identity-restricted` before `/tm` could be reached.
- Corrected release claims: Normal/Heroic/Mythic/Mythic+ route recognition was supported, but strict live route-bound marking was not releasable under then-current Midnight unit-identity restrictions.

## 1.0.0-rc17 — full MDT/runtime release audit

- Fixed MDT 6.2 load-on-demand route initialization: explicit dungeon-session enrichment can silently load `MythicDungeonTools_UI` outside combat and then reread the public MDT DB.
- Prevented a synchronous MDT UI-initializer refresh during the same adapter refresh by deferring it to the next timer tick.
- Additionally bound marker confirmation to the expected MDT `npcID` when available so another NPC type cannot confirm or auto-advance the runtime instruction.
- Defensively bound controller confirmation to the exact assignment ID and made metadata changes refresh the runtime-plan signature.
- Reset dungeon runtime on run entry/start/reset deterministically to the first route pull, regardless of the pull selected in the MDT editor.
- Explicitly reported when the active MDT route did not expose NPC identity.
- Documented that a generic `/tm @mouseover` action can still mark a wrong hostile mouseover before addon confirmation and that identical live clones cannot reliably be mapped to an MDT `cloneIndex`.
- Re-ran complete Lua syntax, module-load, route, macro, SavedVariables, manifest, and ZIP validation for rc17.

## 1.0.0-rc16 — manual runtime and compatibility fixes

- Corrected the secure-button error code in MDT Focus Marker cooperation so a missing secure button is not incorrectly reported as an extra warning.
- Protected the `GetBindingKey` status read with `pcall` and secret-value detection so diagnostics do not fail when the client cannot safely return the binding.
- Documented Blizzard's target-marker macro restriction against marking more than three units in a very short period; Pull Marker therefore continues to require one physical action per marker.
- Re-ran syntax, core logic, manifest, and packaging validation for rc16.

## 1.0.0-rc15 — MDT extension architecture and cleanup

- Made Mythic Dungeon Tools a required host dependency and limited the addon to the Midnight `standard` game type.
- Split the old monolithic bootstrap into separate command, event, and marker-executor modules.
- Removed retired files `Core/StableHash.lua` and `Models/Assignment.lua` and all remaining references to old batch, route-storage, and import models.
- Simplified marker plans into direct pull-assignment lists while keeping route identity separate from marker-plan identity.
- Centralized shared marker, macro, and button names so Focus Marker cooperation no longer maintains duplicate constants.
- Isolated MDT 6.1 legacy access behind an adapter and used only public initializer/navigation contracts for MDT 6.2.
- Confirmed the standalone interface is presentation-only fallback and does not contain a second route source or backend.
- Hardened the dungeon lifecycle for map, instance, difficulty, Challenge Mode, and combat changes.
- Added source-tree checks for TOC order, dead local functions, exact duplicates, unused files, direct marking/chat/network code, and release pollution.
- Expanded the scenario harness with public MDT 6.2, legacy MDT 6.1.20, Focus Marker conflicts, macro ownership, confirmation races, responsive UI, migrations, and randomized routes.

## 1.0.0-rc14 — full frontend, backend, and future-compatibility audit

- Rebuilt the production tree to 18 loaded Lua modules and removed three retired code files plus eighteen outdated audit documents.
- Simplified database, migrations, backend exports, and unused helpers without changing route or execution behavior.
- Centralized dungeon-name normalization while keeping dungeon matching exact and data-driven.
- Allowed MDT 6.2 load-on-demand UI loading only through the official API and only outside combat when dungeon identity was needed for safe automatic activation.
- Fixed route-row actions so one click selects both the exact pull and exact mob instruction.
- Improved manual mode: a confirmed mob remains selected and the UI explicitly asks the user to choose the next unconfirmed row.
- Hardened embedded-view reuse against invalid host values and improved scaling on small screens.
- Confirmed separate ownership boundaries for MDT, MDT Focus Marker, and Pull Marker.
- Added exact MDT 6.2 plugin-contract tests, future-dungeon scenarios, and expanded frontend/backend integration tests.
- Removed production test hooks and moved future-dungeon validation into complete public session flows, including the official Midnight Season 2 pool used at that time.
- Removed a duplicate marker confirmation path: the secure macro uses only the single `/mpm c` handshake and no longer has a second `PostClick` confirmation.
- Hardened dungeon matching for Unicode apostrophes, non-breaking spaces, and modern dashes so names such as `King’s Rest` and `King's Rest` normalize safely to the same dungeon name.

## 1.0.0-rc13 — coordinated MDT Focus Marker integration

- Added an explicit cooperation bridge for MDT's native Focus Marker.
- Namespaced the addon navigation section as `mdtpullmarker` and added direct access to native `marks`.
- Added macro-name, secure-keybind, route-marker and current-pull overlap diagnostics.
- Added free-marker reporting and non-blocking cooperation findings in route validation.
- Added a safe action that enables preserve-existing behavior in both addons without changing assignments or keybinds.
- Refreshes the native Focus Marker secure action through the known MDT 6.1.20 legacy contract; newer public builds receive an explicit reapply/reload warning when no public refresh method exists.
- Added exhaustive eight-marker, group-assignment, actionbar, combat, legacy and public-plugin scenarios.

## 1.0.0-rc12 — verified Mythic Dungeon Tools 6.1.20 compatibility

- Verified the integration contract against the official `MythicDungeonTools` 6.1.20 source tag and the local legacy compatibility harness.
- Added a direct legacy MDT 6.1.x navigation adapter because 6.1.20 exposes `_G.MDT` and not `MythicDungeonToolsAPI`.
- Registered the **Pull Markers** section before MDT's lazy frame initialization and added a `RunAfterFramesInitialized` callback.
- Forced MDT open with `ShowInterface(true)` so `/mpm` and `/mpm map` no longer toggle an already-open MDT window closed.
- Forced `/mpm map` back to the native `maps` section.
- Added a non-destructive standalone fallback when MDT's legacy sidebar was already built before registration.
- Distinguished the known MDT 6.1.20 legacy contract from merely compatible or untested MDT versions.
- Added exact 6.1.20 dynamic, late-load and source-contract harnesses.

## 1.0.0-rc11 — identity-bound confirmation and fail-closed runtime

- Bound delayed marker confirmation to the same mouseover UnitGUID, assignment, pull and route fingerprint.
- Added serialised confirmation timers so stale callbacks cannot clear newer requests.
- Added automatic confirmation expiry without requiring a later raid-target event.
- Registered secure actions for both key-up and key-down binding modes.
- Blocked marker confirmation and pull completion when the execution plan is invalid.
- Added actionable runtime feedback for failed or expired marker confirmations.
- Improved responsive configuration/runtime sizing and runtime command error reporting.
- Expanded the identity, confirmation and static regression coverage.

## 1.0.0-rc10 — action-bar confirmation and final local hardening

- Fixed direct action-bar use so runtime progress is confirmed through a short `/mpm c` handshake.
- Added bounded `RAID_TARGET_UPDATE` handling; stray, wrong and expired events cannot advance progress.
- Added safe migration of addon-owned rc9 smart macros while retaining fail-closed collision protection.
- Resolved the smart macro icon to a numeric FileDataID with a numeric fallback.
- Added direct, delayed, wrong-marker, stray-event and timeout tests for the action-bar workflow.
- Expanded the action-bar, confirmation and static regression coverage.

## 1.0.0-rc9 — guided runtime and comparative adoption

- Added one guided next-marker instruction with verified mouseover confirmation.
- Added optional auto-advance while preserving confirmation in manual mode.
- Reset stale confirmations when marker plans change without a route-structure change.
- Added validated position persistence, runtime lock/reset and responsive step-card layout.
- Added character/account macro fallback, including fallback after a CreateMacro failure.
- Added Addon Compartment tooltips and clearer runtime controls.
- Expanded the runtime, UI and macro regression coverage.

## 1.0.0-rc8 — comparative hardening and scenario audit

- Compared the workflow and safeguards with FocusMarker, FocusMarker Assistant, FocusMarkerGroup, MPlusMarker and current MDT integration patterns.
- Replaced metadata-sensitive `route-v1` identity with structural `route-v2` fingerprints.
- Added lossless upgrade paths for rc7 UID and fingerprint-keyed saved routes.
- Prevented overwriting unrelated user macros named `MDTPM`.
- Aligned the persisted assignment limit with the transaction budget and added explicit preflight validation.
- Clarified in the UI that identical MDT clones cannot be recognized automatically in the dungeon.
- Expanded the deterministic route, collision and randomized regression coverage.

## 1.0.0-rc6 — simplified native MDT workflow

- Replaced the clone-list editor with a three-step setup screen.
- Use MDT's native **Set Target Marker** context menu on exact map mobs.
- Read `enemyAssignments` directly from the active MDT route.
- Added one 246-character smart mouseover macro for all eight markers.
- Added `/mpm`, `/mpm map`, `/mpm macro`, `/mpm run`, and `/mpm standalone`; `/mpm` opens the MDT section first.
- Added a modern route overview and compact pull-by-pull dungeon window.
- Embedded the same setup interface in the official MDT navigation plugin API without force-loading the load-on-demand UI addon.
- Preserved advanced secure buttons and legacy commands as fallback.
- Added native-assignment parsing and planning tests.

## 1.0.0-rc4 — saturation and macro transaction audit

- Reject overlong route identifiers instead of silently truncating them.
- Add hard limits for normalized MDT pulls, enemies and clones.
- Deduplicate malformed public snapshot enemy and clone indices.
- Block all assignment mutations when a route fingerprint is stale.
- Make bulk enemy-type assignments atomic.
- Reuse configuration UI frames to prevent refresh-time frame accumulation.
- Protect all macro read APIs against Lua exceptions.
- Made compatibility-macro refresh transactional within available WoW macro APIs.
- Added rollback for partially created macros and partially edited macro bodies.
- Added mid-plan CreateMacro and EditMacro failure scenarios.
- Add saturation tests for import collisions, oversized snapshots, frame reuse, atomic bulk writes and macro read failures.
- Revalidated the complete project inside the agreed architecture and safety boundaries.

## 1.0.0-rc2 — release consolidation and macro hardening

- Hardened macro compatibility mode against full account macro slots.
- Wrapped `CreateMacro` and `EditMacro` calls so API exceptions no longer escape.
- Added duplicate macro-name detection and fail-closed behavior.
- Corrected the current `EditMacro` call signature.
- Added adversarial macro tests and synchronized release metadata.
- Consolidated Phases 1 through 9 into a release-candidate package.
- Corrected addon title, notes and documentation version drift.
- Added release notes, compatibility matrix, known limitations, release checklist, test manifest and MIT license.
- Retained manual-only secure execution and public-API-only MDT UI integration.
- No new combat automation or protected-action behavior was added.

## 0.8.0-phase8

- Added a public-API-only MDT navigation section.
- Added route and runtime summaries inside MDT.
- Added buttons to open the marker editor and runtime controller.
- Added `/mdtpm mdtui`.
- Added fail-closed feature detection for unsupported MDT UI APIs.

## 0.7.0-phase7

- Added a manual runtime pull controller.
- Added previous/next pull navigation.
- Added previous/next marker instruction navigation.
- Added manual pull completion, automatic manual advance, and reopen.
- Added a compact runtime guidance frame.
- Runtime progress resets when the MDT route fingerprint changes.
- No protected action, targeting, or automatic marker execution was added.

## 0.6.0-phase6

- Added eight fixed secure raid-marker actions.
- Added Star-through-Skull keybindings.
- Added combat-safe compatibility macro mode.
- Added queued secure and macro refresh after combat.
- Preserved the legacy Skull binding alias.


## 0.5.0-phase5

- Added a native configuration window opened with `/mdtpm open`.
- Added pull navigation, per-clone marker selection and assignment clearing.
- Added duplicate-NPC mouseover warnings and route-stale feedback.
- Added a testable immutable configuration view model.
- Retained all secure-action, database, MDT and planner safeguards.

## 0.4.0-phase4

- Added deterministic per-pull marker planning.
- Added priority ordering and bounded batches.
- Added duplicate-marker conflict detection.
- Added identical-mob mouseover warnings.
- Added route-fingerprint, pull, enemy and clone guards.
- Added `/mdtpm plan [pull]`.
- Retained the Phase 1 secure mouseover marker and Phase 2/3 backend.
