# MDT Pull Marker 1.0.0-rc62

MDT Pull Marker is a World of Warcraft Retail addon that turns Mythic Dungeon Tools target assignments into pull-aware marker macros while staying fail-closed around combat, route changes and Midnight messaging restrictions.

## Source layout

- `Core/` - data, validation, database and planning logic
- `Integrations/` - Mythic Dungeon Tools integration boundaries
- `Runtime/` - session and runtime state
- `UI/` - configuration and runtime views
- `Locale/` - localization
- `tests/` - focused Lua 5.1 regression coverage
- `scripts/` - repository audit and deterministic release packaging

The active runtime inventory is defined exclusively by `MDTPullMarker.toc`. Tests, scripts, repository metadata and release documentation are never included in the addon runtime ZIP unless explicitly allowlisted by the deterministic packager.

## Safe operator preview

Before placing or refreshing any execution macro, use `/mdtpm plan` to print the validated marker-plan summary locally. `/mdtpm plan <pull>` prints the exact assignments for one pull. This preview does not create or update macros, apply raid markers, advance pull state, send addon messages or write to raid chat.

For recovery and diagnostics, `/mdtpm status` gives the compact current state and `/mdtpm doctor` gives the detailed route, owner, macro and progression diagnostics. Manual `next`, `prev`, `complete` and `reopen` controls remain available for explicit recovery when route/runtime state needs operator correction.

The AddOn Compartment entry provides the native WoW shortcut: left-click opens the primary MDT Pull Marker interface and right-click opens the dungeon helper.

## Compatibility

The current rc62 source targets the Retail 12.1 interface contract. Mythic Dungeon Tools 6.2.9 was source-reviewed on 2026-08-28; the public `Modules/API.lua` contract used by the integration is unchanged from the previously reviewed 6.2.x source. Versions in the configured 6.1.17 through 6.2.x compatibility range that are not explicitly source-verified continue to be reported as compatible-range rather than silently promoted to verified-source. The addon does not duplicate MDT dungeon/forces data; Season 2 route and force corrections remain owned by MDT.

Grouped marker ownership is settled before a Mythic+ challenge and frozen for that challenge. Midnight chat/addon-message lockdown is treated as expected communication suspension, and positively losing the frozen owner fails closed instead of electing a replacement without communication.

Automatic marking remains capped at three targets per macro activation, matching Blizzard's current target-marker restriction.

## Quality and release model

GitHub Actions compile all Lua with Lua 5.1, run focused regressions, audit repository hygiene and verify deterministic packaging. Actions are pinned to immutable commit SHAs and Dependabot is configured to maintain those pins.

Generated ZIPs and checksums are release outputs, not source files. Tagged `v<VERSION>` builds are rebuilt from source, checked twice for determinism, SHA-256 hashed, attested and published as GitHub Release assets. See `RELEASING.md` for the live-client and CurseForge release gate.

`COMPARABLE_ADDON_AUDIT-2026-08-21.md` records the comparison against Mythic Dungeon Tools, MDT Next Pull Tracker, WarpDeplete, Angry Keystones and MythicPlusTimer, including features deliberately not adopted because they would broaden the addon's safety boundary.

## Public release status

The source is Season 2-ready. A stable public release still requires the live Retail smoke-test matrix on the intended client/MDT versions. Pre-release versions such as `1.0.0-rc62` should remain preview/beta distribution until that gate passes.
