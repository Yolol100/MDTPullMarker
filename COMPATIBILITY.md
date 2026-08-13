# Compatibility — 1.0.0-rc57

## World of Warcraft

The package targets Retail interfaces `120100` and `120007` as declared in `MDTPullMarker.toc`. Current namespaced APIs are preferred where available, with narrowly scoped legacy fallbacks only where compatibility requires them.

Key current API paths include:

- `C_AddOns` for addon metadata/loading when available.
- `C_ChatInfo` for addon-prefix registration and grouped addon messages.
- `C_CombatLog.GetCurrentEventInfo` as the primary combat-log reader; the deprecated global remains a compatibility fallback.
- `C_CVar` for action-button behavior where available.
- `C_ChallengeMode` for active Mythic+ map identity.
- `C_TooltipInfo` for localized creature-name resolution.
- `C_Timer` for bounded delayed refreshes/heartbeats.

Protected macro creation/editing is performed only outside combat lockdown. Client-only taint/protected-action behavior still requires the live checklist.

## Mythic Dungeon Tools

The adapter contains compatibility handling for the tested 6.1.x monolithic/global layout and the 6.2.x public core + load-on-demand UI layout represented in the source-verified version table. Versions newer than the configured tested range are surfaced as untested rather than silently claimed compatible.

The integration prefers the public `MythicDungeonToolsAPI` surface. Legacy `_G.MDT` access is isolated as a compatibility path. MDT 6.2.x captured enemy metadata is explicitly partial by enemy type; it is supplemental same-name evidence, not proof of a complete dungeon inventory.

## Route identity

- UID-backed routes resolve strictly by UID.
- UID-less routes resolve strictly by the saved membership fingerprint.
- A missing UID-less fingerprint does not fall back to a unique same-name route; the user must rebind.
- A Challenge Map ID cannot be newly shared by two saved dungeon bindings.
- An active challenge map is authoritative; ambiguous/corrupt binding state fails closed.

The stricter UID-less policy intentionally favors identity safety over automatic continuity after pull-membership edits. Marker-only changes do not change the membership fingerprint and remain compatible with the same binding.

## Group owner protocol

Current owner safety requires the rc52+ protocol generation. Older builds can disagree about deterministic owner selection. rc57 detects a live pre-rc52 peer and keeps the current client passive instead of risking two active marker owners.

All marker operators in a group should use a current build.

## Developer compatibility

The runtime is written for WoW's Lua environment. The canonical repository gate requires an actual Lua 5.1 interpreter. A newer compatible interpreter may be used only with the explicit `MPM_ALLOW_COMPATIBLE_LUA=1` diagnostic fallback, which is reported as non-certifying. CI installs and executes Lua 5.1 explicitly.
