# Compatibility — 1.0.0-rc62

## World of Warcraft

MDT Pull Marker targets Retail interfaces `120100` and `120007` as declared in `MDTPullMarker.toc`. The runtime prefers current namespaced APIs (`C_AddOns`, `C_ChatInfo`, `C_CombatLog`, `C_CVar`, `C_ChallengeMode`, `C_TooltipInfo`, `C_Timer`) and keeps narrowly scoped legacy fallbacks where required.

For Midnight Season 2, automatic bulk marking remains capped at three target-marker operations per macro activation. This matches Blizzard's current macro restriction and is guarded by regression coverage that rejects a fourth assignment.

Client-specific combat, UI and action-button behavior still requires live Retail validation before public release.

## Mythic Dungeon Tools

The adapter contains compatibility handling for the MDT 6.1.x monolithic/global layout and the 6.2.x public-core plus load-on-demand UI layout. Versions beyond the configured range are reported as untested rather than silently accepted.

The current compatibility range includes MDT 6.2.5. The 2026-08-22 source review pins upstream tag `6.2.5` at commit `68e9378b7e894ebdf990f8759657f70c611742fa`. Relative to 6.2.4, the release contains dungeon-data corrections plus one relevant Focus Marker safety change: when no Focus Marker is selected while `preserveExistingTargetMarkers` is enabled, MDT now leaves an existing target marker untouched instead of emitting a clearing target-marker action. The setting name and Focus Marker storage contract consumed by `MDTFocusMarkerBridge` are unchanged, so no MDTPullMarker runtime adapter change is required.

Upstream 6.2.x dungeon-data corrections continue to flow through the installed MDT route/enemy data. MDT Pull Marker intentionally does not maintain a duplicate Season 2 enemy-force table, so corrected groupings, names, boss data, positions, health values and enemy forces remain MDT-owned truth rather than a local fork.

A version marked `source-verified` means its adapter/source contract was explicitly reviewed. The latest live-client validation remains a separate release gate; source review alone does not prove in-game behavior.

The integration prefers `MythicDungeonToolsAPI` where the required method is available; legacy `_G.MDT` access is isolated as a fallback. Captured MDT enemy metadata is treated as supplemental evidence rather than proof of a complete dungeon inventory.

## Route and group safety

- UID-backed routes resolve by UID.
- UID-less routes resolve by their saved membership fingerprint.
- Missing or ambiguous route identity fails closed instead of binding by name alone.
- Active Challenge Map identity is authoritative.
- The current rc62 build detects incompatible pre-rc52 peers and remains passive rather than risking multiple active marker owners.
- The current rc62 build also rejects secret, malformed, non-string and oversized ownership-protocol payloads before parsing or peer-state mutation.
- Only eligible clients that have announced this add-on participate in grouped marker-owner election; unrelated tanks or leaders cannot suppress all marking.
- Grouped ownership is settled before an active Mythic+ challenge and frozen for the full challenge.
- Midnight chat/addon-message lockdown is treated as expected transport suspension; the running challenge does not send ownership heartbeats or re-elect between combats.
- If the frozen owner is positively proven to have left the group during a challenge, ownership fails closed rather than electing a replacement without peer communication.
- Midnight pull-death evidence uses the supported `UNIT_DIED` event. A restricted/secret GUID remains advisory and cannot complete a pull.

All marker operators in a group should use a current build.

## Repository validation

The checked-in GitHub workflows install Lua 5.1, compile the Lua source, run the focused regression suite, execute the repository audit and verify the active TOC/package inventory. The `scripts/` directory contains the current repository-audit and deterministic release-build helpers; it is tooling only and is not part of the WoW runtime inventory.
