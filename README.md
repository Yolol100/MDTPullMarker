# MDT Pull Marker 1.0.0-rc54

MDT Pull Marker reads raid-target assignments from Mythic Dungeon Tools (MDT) and turns the chosen route for each dungeon into prebuilt, pull-specific combat macros. MDT remains authoritative for pull order and raid icons: configured markers are never silently remapped.

## Recommended workflow

1. Select the MDT route you want to use for a dungeon.
2. Use **Bind selected route** or `/mpm bind` outside combat.
3. The addon stores that chosen route for that dungeon. Other dungeons can keep their own chosen route at the same time.
4. The full bound route is read in advance. Safe marked pulls receive stable macros such as `MPM001A`, `MPM002A`, `MPM002B` and `MPM010C`.
5. One macro contains at most three marker operations. A pull can use A/B/C and therefore cover up to eight raid icons when the names fit the 255-byte WoW macro budget.
6. Put the macros you use on your action bars. `/mpm macro 4a` picks up pull 4 batch A.
7. In the matching dungeon, on the elected marker-owner client and outside combat, the prepared bodies become active. In every other context they are safely parked.
8. Pull the pack and press the macro for that MDT pull. For B/C batches, follow the addon's conservative ~4 second retry guidance.
9. During a chain-pull, a later pull's macro is already available. Pressing it switches logical execution to that exact pull without rewriting a protected macro during combat.

The visible MDT dropdown does not silently replace a saved binding. Rebinding a different route changes only that dungeon's chosen route.

## Per-dungeon route storage

rc54 stores route bindings by MDT dungeon identity. For example:

- Dungeon A -> chosen Route A
- Dungeon B -> chosen Route B
- Dungeon C -> chosen Route C

Entering an active Mythic+ dungeon makes that dungeon context authoritative. A binding from another dungeon is never used as a fallback inside the active key. `/mpm unbind` clears only the active dungeon's binding.

A route may be bound before a future season exposes that dungeon through `C_ChallengeMode.GetMapTable()`. If its Challenge Map ID was therefore unavailable at bind time, rc54 can recover that binding once the dungeon becomes active by requiring one unique match against MDT's current client-localized dungeon name for the saved MDT dungeon index. This remains valid if the client locale changed after binding. The bind-time name is only a fallback, and a binding that already carries a different map ID is never repurposed.

A Challenge Map ID cannot be newly assigned to two different saved dungeon bindings. If older/corrupt SavedVariables already contain an ambiguous map or name mapping, active Mythic+ route resolution fails closed instead of falling back to the currently visible MDT route.

## Pull macros

Pull numbers follow MDT's original pull indexes:

- 1-3 marker actions: usually `MPM###A`
- 4-6: usually A + B
- 7-8: usually A + B + C
- no marker work: no route macro is needed
- unsafe exact-name identity: the pull becomes `manual-required`

Long or multibyte names can force an earlier split because generated macro bodies are validated by actual UTF-8 byte length and may never exceed 255 bytes.

## Chain-pulls, skips and overlap

Bound mode keeps progress per marked pull instead of only one global current-pull death context.

- Pull 1 can remain active while pull 2 or pull 3 is started.
- The addon keeps separate pending submission/death state for overlapping marked pulls.
- Jumping forward marks untouched intermediate marked pulls as skipped instead of pretending they were completed.
- Returning to a skipped pull clears its skipped state and engages it normally.
- Readable death events are assigned only when they identify one active pull unambiguously. If one death could belong to multiple active pulls, progression fails closed instead of guessing.
- A submitted pull with readable combat-log access but no expected death evidence does not auto-complete at combat end.
- If Retail makes the relevant combat-log identity genuinely secret/restricted, death evidence remains advisory; a restricted state is kept distinct from an ordinary no-evidence state.

The player's macro press remains the authoritative signal for an intentional chain-pull or jump, but a normal readable combat with zero expected death evidence is not treated as proof that the pull completed.

## Same-name safety

`/targetexact` cannot prove which physical MDT clone was selected when multiple simultaneously reachable mobs share the same visible name. Because players may skip pulls or chain non-adjacent pulls, rc54 checks the complete bound route, not only neighboring pulls.

When MDT exposes dungeon enemy metadata, the planner also uses the known clone totals for captured enemy types. A duplicate proven by that metadata becomes `manual-required` even when the duplicate is outside the selected route. MDT 6.2.x metadata captured through the UI hook is explicitly labelled `captured-enemy-types`/`cached-enemy-types`: those records contain the full clone list for each known enemy type, but are not presented as proof that every other enemy type in every sublevel has been enumerated. Route-wide ambiguity remains the guaranteed baseline.

If a marked target's resolved visible name is proven ambiguous by the bound route or known dungeon metadata, affected automatic execution becomes `manual-required`. The addon never falls back to `/targetenemy` or another guessing cycle.

## Macro lifecycle and action-bar stability

- Route macro names are stable: `MPM###A/B/C`.
- The same names are reused between dungeons; the addon does not create a separate namespace for every dungeon.
- A shorter route no longer deletes extra addon-owned route macros. Extras are rewritten to the safe idle body and kept at the same macro index, preserving existing action-bar references where the client supports normal macro references.
- Returning to a route that needs those names reactivates the existing macro slots instead of recreating them.
- An unrelated personal macro with an `MPM###A/B/C` name is never overwritten or deleted.
- Managed ownership requires both a recognized body and the dedicated addon icon.
- Create/edit/park/delete operations are read back and verified; API return values alone are not trusted.
- Partial refresh failures fail closed. Existing managed route macros are parked first; deletion is only an emergency fallback when an active managed body cannot be made inert.
- New macros prefer account-wide macro space and fall back to character space without assuming a hard-coded character capacity.
- Macro mutation is never attempted during combat lockdown.

When the last route binding is intentionally removed, the addon may retire its route macros to return fully to legacy mode and free macro slots. If other dungeon bindings still exist, route macros are parked instead.

In grouped play the marker-owner election must be settled before combat starts. All clients derive one deterministic roster anchor using tank, leader, DPS, healer and then stable-name priority; only that roster member can become the marker owner when its local eligibility and addon communication are both proven. Peer silence never promotes a lower member, because a missing message cannot prove that another addon client is absent.

When a new pre-combat election starts, managed execution surfaces are immediately parked before the settle window begins. They are reactivated only after the election has settled and this client is again proven to be the owner. If combat starts while ownership is still settling or otherwise unproven, rc54 freezes a passive owner state for that entire combat. Peer heartbeats, roster changes and settle callbacks may prepare the next election, but they cannot change the effective combat owner during that combat.

A failed addon-message send immediately drops group ownership and keeps the client passive. Registration is retried later at safe group/world/heartbeat boundaries; recovery starts a fresh settle window rather than silently restoring an old owner.

## Important execution limits

Active route bodies begin with `/stopmacro [nocombat]`. They intentionally do not target or mark from an accidental out-of-combat press.

The final `/mpm b ...` callback proves that the correct managed macro reached its callback; it cannot independently prove that every preceding protected `/tm` command succeeded. The addon therefore records **submitted attempts**, not fictional per-unit confirmations. The ~4 second pacing is a conservative local safety window, not an official exact Blizzard reset duration.

Exact-name execution necessarily changes the player's target while the macro walks its targets. rc54 does not add an unverified target-history trick that could weaken fail-closed targeting or push valid three-target bodies over the 255-byte limit.

Manual runtime navigation can still move between prebuilt route pulls during combat. Commands that mutate completion state (`complete` and `reopen`) are held until combat ends.

## Legacy fallback

If the active dungeon has no saved route binding, the rc44-compatible fallback remains available:

- `MDTPM1` + optional `MDTPM2`
- maximum six automatic marker assignments per current marked pull
- macro bodies refresh only at safe out-of-combat boundaries
- uninterrupted chain-pulls cannot receive a rewritten next-pull body until combat ends

Bound-route mode is recommended.

## Diagnostics

- `/mpm routes` - inspect routes for the selected dungeon
- `/mpm macros` - refresh/inspect the active dungeon's bound macro set
- `/mpm macro 4a` - pick up a specific route macro
- `/mpm doctor` - route, dungeon, owner/communication, macro, parked-slot and overlap diagnostics

Automated compatibility fixtures in the source+tests package cover MDT 6.1.20's monolithic/global layout and the MDT 6.2.x core + load-on-demand UI layout. The runtime repository/package does not contain that test suite, so these fixtures are not a substitute for the final Retail client smoke test in `LIVE_TEST_CHECKLIST.md`.
