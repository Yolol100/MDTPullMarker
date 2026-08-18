# MDT Pull Marker 1.0.0-rc58

This repository contains the current World of Warcraft addon source for MDT Pull Marker.

## Maintained source layout

- `Core/` - data, validation, database and planning logic
- `Integrations/` - Mythic Dungeon Tools integration boundaries
- `Runtime/` - session and runtime state
- `UI/` - configuration and runtime views
- `Locale/` - localization
- `tests/` - focused Lua 5.1 regression coverage
- `scripts/` - repository audit and deterministic release packaging helpers

The active runtime inventory is defined by `MDTPullMarker.toc`; `tests/` and `scripts/` are repository/release tooling and are not loaded by WoW.

## Repository assurance status

The current rc58 tree contains a Lua 5.1 regression harness in `tests/` covering event inventory, input hardening, MDT integration boundaries, marker execution, grouped marker ownership, migrations, pull-death tracking, runtime control and smart macro management. `scripts/audit_repository.py` and `scripts/build_release.py` provide repository and package validation in addition to the checked-in GitHub workflows.

Grouped marker ownership is elected before a running Mythic+ challenge and then frozen for the challenge. Midnight chat/addon-message lockdown is treated as an expected communication suspension rather than as ownership loss; if the frozen owner is positively proven to have left the group, marking fails closed instead of electing a replacement without communication.

The checked-in GitHub workflows compile Lua sources with Lua 5.1, run the regression harness, audit the repository and verify release/package invariants.

The three historical duplicate source paths remain in the repository only as inert retired placeholders; active runtime code is defined by the TOC.

Before a public release, validate the addon on the current Retail client and verify the current Mythic Dungeon Tools integration, grouped operation, route changes, persistence and UI behavior.
