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

The current rc58 tree does not contain the previously documented `tests/`, `scripts/`, `types/` or `docs/` directories. Those absent files are therefore not claimed as release evidence in this README.

Before a public release, validate the addon on the current Retail client and verify the current Mythic Dungeon Tools integration, grouped operation, route changes, persistence and UI behavior.
