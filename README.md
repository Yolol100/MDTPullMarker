# MDT Pull Marker

> **Other engineering · Lua · World of Warcraft Retail · Mythic Dungeon Tools integration**

This project sits outside my primary WordPress portfolio and is included as additional engineering work.

MDT Pull Marker is a World of Warcraft Retail add-on that turns Mythic Dungeon Tools target assignments into pull-aware marker macros.

## Requirements

- World of Warcraft Retail
- Mythic Dungeon Tools

## Installation

1. Place the `MDTPullMarker` folder in `World of Warcraft/_retail_/Interface/AddOns/`.
2. Make sure `MDTPullMarker.toc` is directly inside that folder.
3. Enable **MDT Pull Marker** in the WoW AddOns menu.

## Usage

Use `/mdtpm` in game. Useful commands include:

- `/mdtpm plan` — preview the validated marker plan
- `/mdtpm status` — show current state
- `/mdtpm doctor` — show detailed diagnostics

The AddOn Compartment entry can also open the add-on interface.

## Repository structure

This repository intentionally contains only the files needed by the add-on at runtime, plus its license and this README.

- `Core/` — validation, database and planning logic
- `Integrations/` — Mythic Dungeon Tools integration
- `Runtime/` — active dungeon and marker runtime
- `UI/` — configuration and runtime interface
- `Locale/` — localization
- `Bindings.xml` — WoW key bindings
- `MDTPullMarker.lua` — add-on bootstrap/shared state
- `MDTPullMarker.toc` — WoW add-on manifest

## License

MIT. See `LICENSE`.
