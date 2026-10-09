# MDT Pull Marker

> **Other engineering · Lua · World of Warcraft Retail · Mythic Dungeon Tools integration**

**Developer profile:** [Andrew Baeten](https://github.com/Yolol100) · [Portfolio cases](https://andrewbaeten.nl/category/cases)

MDT Pull Marker is a World of Warcraft Retail add-on that turns Mythic Dungeon Tools route and target information into validated pull-aware marker plans and guarded smart-macro workflows.

This project sits outside my primary WordPress portfolio and is included as additional engineering work.

## What it demonstrates

| Area | Implementation |
| --- | --- |
| Route integration | Mythic Dungeon Tools adapter, route snapshots and target resolution |
| Planning | Pull-aware marker planning and route-specific macro plans |
| Runtime safety | Validation, ambiguity handling and fail-closed behaviour for unsafe targets |
| State | SavedVariables database, migrations and dungeon-session tracking |
| Protected actions | Smart-macro and marker execution kept behind WoW runtime constraints |
| UI | Configuration, runtime status and AddOn Compartment integration |

## Requirements

- World of Warcraft Retail
- Mythic Dungeon Tools

## Current MDT compatibility

Upstream MDT version **6.3.5** (8 October 2026) has been compared at source/API level with 6.2.12. Public and legacy navigation methods remain present, but this is **not** an in-game regression test. The add-on deliberately classifies MDT 6.3.x as `untested-newer` and warns while retaining its existing defensive route validation. It must not be described as fully verified on MDT 6.3.5 until a representative World of Warcraft client test passes.

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

## Safety model

The add-on does not treat every route target as safe to automate. Route data is normalized and validated before marker plans are exposed. When a marked creature name is ambiguous or the intended physical target cannot be addressed safely, the pull is parked instead of risking a marker on the wrong unit.

Runtime state, marker ownership and pull progression are handled separately from route parsing so stale or conflicting state can be rejected rather than silently reused.

## Repository structure

- `Core/` — validation, database, migrations, route snapshots and marker planning
- `Integrations/` — Mythic Dungeon Tools adapters and creature/marker bridges
- `Runtime/` — dungeon sessions, pull tracking, marker ownership and smart-macro execution
- `UI/` — configuration and runtime interface
- `Locale/` — localization
- `Bindings.xml` — WoW key bindings
- `MDTPullMarker.lua` — add-on bootstrap and shared state
- `MDTPullMarker.toc` — WoW add-on manifest and runtime load order

## Portfolio context

MDT Pull Marker is included as supporting engineering work because it shows stateful Lua integration, defensive validation and runtime behaviour inside a constrained game API rather than WordPress-specific development.

## License

MIT. See `LICENSE`.
