# MDT Pull Marker 1.0.0-rc58

This repository contains the current World of Warcraft addon source for MDT Pull Marker.

## Maintained source layout

- `Core/` - data, validation, database and planning logic
- `Integrations/` - Mythic Dungeon Tools integration boundaries
- `Runtime/` - session and runtime state
- `UI/` - configuration and runtime views
- `Locale/` - localization

The active runtime inventory is defined by `MDTPullMarker.toc`.

## Repository assurance status

The current rc58 tree contains a focused Lua 5.1 regression harness in `tests/`. It covers the Midnight-safe `UNIT_DIED` event path and grouped marker-owner candidate filtering. The previously documented broader `scripts/`, `types/` and `docs/` directories are absent and are therefore not claimed as release evidence here.

The checked-in validation workflow compiles Lua sources with Lua 5.1, runs the focused regression harness and verifies the TOC inventory.

The three historical duplicate source paths remain in the repository only as inert retired placeholders; active runtime code is defined by the TOC.

Before a public release, validate the addon on the current Retail client and verify the current Mythic Dungeon Tools integration, grouped operation, route changes, persistence and UI behavior.
