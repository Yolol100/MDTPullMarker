# Compatibility — 1.0.0-rc58

## World of Warcraft

MDT Pull Marker targets Retail interfaces `120100` and `120007` as declared in `MDTPullMarker.toc`. The runtime prefers current namespaced APIs (`C_AddOns`, `C_ChatInfo`, `C_CombatLog`, `C_CVar`, `C_ChallengeMode`, `C_TooltipInfo`, `C_Timer`) and keeps narrowly scoped legacy fallbacks where required.

Client-specific combat, UI and action-button behavior still requires live Retail validation before public release.

## Mythic Dungeon Tools

The adapter contains compatibility handling for the MDT 6.1.x monolithic/global layout and the 6.2.x public-core plus load-on-demand UI layout. Versions beyond the configured range are reported as untested rather than silently accepted.

A version marked `source-verified` means its adapter/source contract was explicitly reviewed. It does **not** mean the current public rc58 tree has run that version in a live Retail client. Live compatibility must therefore be rechecked before release.

The integration prefers `MythicDungeonToolsAPI`; legacy `_G.MDT` access is isolated as a fallback. Captured MDT enemy metadata is treated as supplemental evidence rather than proof of a complete dungeon inventory.

## Route and group safety

- UID-backed routes resolve by UID.
- UID-less routes resolve by their saved membership fingerprint.
- Missing or ambiguous route identity fails closed instead of binding by name alone.
- Active Challenge Map identity is authoritative.
- rc58 detects incompatible pre-rc52 peers and remains passive rather than risking multiple active marker owners.
- Only eligible clients that have announced this add-on participate in grouped marker-owner election; unrelated tanks or leaders cannot suppress all marking.
- Grouped ownership is settled before an active Mythic+ challenge and frozen for the full challenge.
- Midnight chat/addon-message lockdown is treated as expected transport suspension; the running challenge does not send ownership heartbeats or re-elect between combats.
- If the frozen owner is positively proven to have left the group during a challenge, ownership fails closed rather than electing a replacement without peer communication.
- Midnight pull-death evidence uses the supported `UNIT_DIED` event. A restricted/secret GUID remains advisory and cannot complete a pull.

All marker operators in a group should use a current build.

## Repository validation

The checked-in GitHub workflows install Lua 5.1, compile the Lua source, run the focused regression suite, execute the repository audit and verify the active TOC/package inventory. The `scripts/` directory contains the current repository-audit and deterministic release-build helpers; it is tooling only and is not part of the WoW runtime inventory.
