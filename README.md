# MDT Pull Marker 1.0.0-rc58

MDT Pull Marker converts raid-target assignments from a chosen Mythic Dungeon Tools route into prebuilt, pull-specific World of Warcraft macros. MDT remains authoritative for pull membership and marker choices; the addon focuses on deterministic planning, safe protected-action preparation, multiplayer owner election and conservative progression.

## Safety model

The addon deliberately fails closed around uncertain execution state:

- Managed route macros are executable only for a matching dungeon/session and the elected marker-owner client.
- Route bodies begin with `/stopmacro [nocombat]`; accidental out-of-combat presses do not target or mark.
- A route or session invalidation parks known addon-managed execution before an asynchronous rebuild is allowed to reactivate it.
- Bound MDT route membership is identity-critical. UID-backed routes resolve by UID; UID-less routes resolve by the exact saved membership fingerprint and require explicit rebind when that fingerprint disappears.
- Automatic targeting uses `/targetexact`; known same-name ambiguity becomes `manual-required` rather than guessing a physical clone.
- A macro callback records submission intent, not proof that preceding protected `/tm` commands succeeded.
- Automatic completion requires a positive readable death verdict. API/read failures, incomplete deaths, ambiguity and proven death events whose destination identity is restricted all block auto-completion; restricted evidence remains visible diagnostically and can be resolved only by an explicit manual completion outside combat.
- Grouped ownership uses the rc52+ deterministic owner protocol. A current client stays passive when it discovers an incompatible pre-rc52 addon peer.

See `docs/SAFETY_MODEL.md` for the detailed invariants.

## Workflow

1. Select a route in MDT.
2. Outside combat, use `/mpm bind`.
3. The route is normalized and planned in advance.
4. Safe marked pulls receive stable macros such as `MPM001A`, `MPM004A`, `MPM004B` and `MPM004C`.
5. Put the macros you need on your action bars.
6. Enter the matching dungeon. The macros remain parked unless the session, binding and marker-owner gate are all proven.
7. Pull the pack and press the macro for that exact MDT pull. B/C batches retain the conservative local pacing window.

A pull can use at most eight raid icons across A/B/C. Each macro contains at most three marker operations and is checked against WoW's 255-byte macro budget using actual Lua string bytes.

## Route edits

Marker or route changes invalidate prepared execution. Outside combat, MDT enemy/pull mutation interactions park managed execution synchronously before the deferred route rebuild; redraw hooks provide a second synchronous signal and the lightweight 250 ms route signature watcher is fallback detection. If a route-changing interaction occurs during combat, the validated execution contract is frozen and rebuilt after combat rather than applying a partially observed route. The watcher covers both bound and legacy/current-route mode, including UID-route membership, marker assignments and current-pull changes. A membership edit changes a UID-less route fingerprint, so that binding intentionally requires an explicit rebind rather than silently accepting another same-name route.

## Same-name targeting

The complete bound route is the guaranteed same-name safety scope. When MDT exposes/caches additional enemy metadata, that metadata can prove more ambiguity, but partial `captured-enemy-types` / `cached-enemy-types` data is never represented as a complete dungeon inventory.

If the resolved visible name is known to represent multiple route/dungeon candidates, automatic execution is parked for that pull. The addon never falls back to an unfiltered `/targetenemy` cycle.

## Multiplayer ownership

All current clients use the same deterministic priority: tank, leader, DPS, healer, stable full name. A pre-combat settle window parks execution until ownership is proven. Combat freezes the effective owner for that combat.

Temporary communication failures drop grouped ownership immediately. Prefix registration and send success are checked separately; `DuplicatePrefix` is accepted only when `IsAddonMessagePrefixRegistered` independently proves the prefix is registered. Missing/failed sends remain fail-closed.

Pre-rc52 peers are treated as owner-protocol incompatible because older builds did not all share the current deterministic safety model. The current client therefore stays passive while such a live peer is detected.

## Diagnostics

Useful commands:

- `/mpm routes` — inspect routes for the selected dungeon.
- `/mpm bind` / `/mpm unbind` — manage the active dungeon binding.
- `/mpm macros` — refresh and inspect the bound macro set.
- `/mpm macro 4a` — pick up pull 4 batch A.
- `/mpm doctor` — show session, route, owner, macro and death-tracking diagnostics.
- `/mdtpm validate` — validate the active route/plan.

## Repository layout

```text
Core/          normalized data, validation, database, marker planning and macro grammar
Integrations/  MDT and localization integration boundaries
Runtime/       session, ownership, secure macro lifecycle, execution and progression
UI/            configuration and runtime views
types/         LuaCATS developer-only model types
tests/         executable regression and repository contract tests
scripts/       verification and packaging
docs/          architecture, safety model and Retail live-test checklist
```

File names intentionally match their exported modules (`RuntimeController.lua` → `Addon.RuntimeController`, `ConfigurationUI.lua` → `Addon.ConfigurationUI`, `MDTIntegration.lua` → `Addon.MDTIntegration`).

## Development quality gates

Run:

```bash
bash scripts/check.sh
```

The canonical gate requires a real Lua 5.1 interpreter, executes targeted owner/death/route/macro regressions, checks repository-wide safety contracts, proves deterministic packaging across different source mtimes, and verifies exact ZIP inventory/metadata/bytes. In constrained environments `MPM_ALLOW_COMPATIBLE_LUA=1` permits a clearly labeled non-certifying fallback. `.luarc.json`, LuaCATS declarations and `.stylua.toml` remain contributor contracts; formatting is not a release gate until the repository has a separately reviewed formatting-only baseline.

Static/model checks do not replace a real Retail client test. Before release, complete `docs/LIVE_TEST_CHECKLIST.md`, especially secure macro/taint behavior, action-bar persistence, real group communication and combat-log restriction cases.


## Software assurance

The rc58 source tree includes bidirectional safety traceability (`docs/TRACEABILITY.md`), an SFMEA-style hazard register (`docs/HAZARDS.md`), pinned MDT compatibility fixtures, mutation/property/resource regressions, Lua 5.1 CI and a cryptographically pinned Lua Language Server diagnostic gate. The runtime package remains limited to addon files loaded by WoW.
