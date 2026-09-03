# Compatibility — 1.0.0-rc63

## World of Warcraft

MDT Pull Marker targets Retail interfaces `120100` and `120007` as declared in `MDTPullMarker.toc`. The runtime prefers current namespaced APIs (`C_AddOns`, `C_ChatInfo`, `C_CombatLog`, `C_CVar`, `C_ChallengeMode`, `C_TooltipInfo`, `C_Timer`) and keeps narrowly scoped legacy fallbacks where required.

For Midnight Season 2, automatic bulk marking remains capped at three target-marker operations per macro activation. This matches Blizzard's current macro restriction and is guarded by regression coverage that rejects a fourth assignment.

Client-specific combat, UI and action-button behavior still requires live Retail validation before public release.

## Mythic Dungeon Tools

The adapter contains compatibility handling for the MDT 6.1.x monolithic/global layout and the 6.2.x public-core plus load-on-demand UI layout. Versions beyond the configured range are reported as untested rather than silently accepted.

The current compatibility review covers MDT 6.2.12 at upstream commit `5c9413ffde853e71c8fe3f1864dc5ae42e301f64` on 2026-09-03. The public `Modules/API.lua` blob remains `4b99a76a8d65f6078f0df42525c2b3d2df87ef50`, unchanged from the previously reviewed 6.2.x source. `Modules/Presets.lua` still exposes the `db.currentDungeonIdx`, `db.currentPreset` and `db.presets` route-selection layout consumed by the adapter. `Core/Bootstrap.lua` still exposes `RegisterUIInitializer`, and the load-on-demand UI plugin still provides `RegisterNavigationSection`, `SetCurrentSection` and `GetNavigationSectionContentFrame` for the embedded panel path.

MDT 6.2.11 corrected enemy placements and pull groupings in King's Rest, Ruby Life Pools, Temple of Sethraliss and The Blinding Vale. Those corrections flow through the installed MDT route/enemy data; MDT Pull Marker intentionally does not maintain a duplicate Season 2 enemy-force table. MDT 6.2.12 changes the Focus Marker account-macro slot lookup to Blizzard's namespaced macro constant. The Focus Marker saved settings consumed by the bridge, including `preserveExistingTargetMarkers`, remain compatible, so no marker-execution algorithm change is required in MDTPullMarker.

The upstream drift baseline now requires and fingerprints the release changelog, public API, Focus Marker implementation, preset route-selection source, core UI initializer and load-on-demand UI plugin bootstrap. Removing any of those required watch surfaces makes the checker fail validation rather than silently reducing coverage.

A version marked `source-verified` means its adapter/source contract is present in the runtime's explicit verified-version allowlist. MDT 6.2.12 remains inside the accepted 6.2.x compatibility range and this repository review does not silently expand that runtime allowlist. Live-client validation remains a separate release gate, and source review alone does not prove in-game protected-action behavior.

The integration prefers `MythicDungeonToolsAPI` where the required method is available; legacy `_G.MDT` access is isolated as a fallback. Captured MDT enemy metadata is treated as supplemental evidence rather than proof of a complete dungeon inventory.

## Route and group safety

- UID-backed routes resolve by UID.
- UID-less routes resolve by their saved membership fingerprint.
- Missing or ambiguous route identity fails closed instead of binding by name alone.
- Active Challenge Map identity is authoritative.
- The current rc63 build detects incompatible pre-rc52 peers and remains passive rather than risking multiple active marker owners.
- The current rc63 build also rejects secret, malformed, non-string and oversized ownership-protocol payloads before parsing or peer-state mutation.
- Only eligible clients that have announced this add-on participate in grouped marker-owner election; unrelated tanks or leaders cannot suppress all marking.
- Grouped ownership is settled before an active Mythic+ challenge and frozen for the full challenge.
- Midnight chat/addon-message lockdown is treated as expected transport suspension; the running challenge does not send ownership heartbeats or re-elect between combats.
- If the frozen owner is positively proven to have left the group during a challenge, ownership fails closed rather than electing a replacement without peer communication.
- Midnight pull-death evidence uses the supported `UNIT_DIED` event. A restricted/secret GUID remains advisory and cannot complete a pull.

All marker operators in a group should use a current build.

## Repository validation

The checked-in GitHub workflows install Lua 5.1, compile the Lua source, run the focused regression suite, execute the repository audit, regression-test upstream-drift failure modes and verify the active TOC/package inventory. The `scripts/` directory contains the current repository-audit and deterministic release-build helpers; it is tooling only and is not part of the WoW runtime inventory.
