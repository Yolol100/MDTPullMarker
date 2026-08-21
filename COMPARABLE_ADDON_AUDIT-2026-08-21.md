# Comparable Add-on Audit — 2026-08-21

This checklist records patterns reviewed from comparable Mythic+ addons and the decisions taken for MDT Pull Marker. It is a design/evidence document; it does not copy third-party code.

## Compared projects

1. **Mythic Dungeon Tools** — route planning, pull grouping, map context, import/export and clear separation between route data and runtime consumers.
2. **Mythic Dungeon Tools - Next Pull Tracker** — current/upcoming pull presentation, scenario-forces progression, manual next/previous/revert recovery, auto lifecycle and compact diagnostics.
3. **WarpDeplete** — demo mode, compact current-pull information, low-memory emphasis, localization and optional display customization.
4. **Angry Keystones** — precise enemy-forces presentation, objective-tracker augmentation, lightweight configuration and per-mob forces context.
5. **MythicPlusTimer** — demo/unlocked presentation, objective timing context, persistent UI state and compact operator commands.

## Adoption checklist

- [x] Keep MDT authoritative for route membership, pulls and enemy-force data instead of duplicating season data.
- [x] Keep fail-closed route fingerprint/validation before any marker execution.
- [x] Keep manual pull recovery controls (`next`, `prev`, `complete`, `reopen`) and detailed `status` / `doctor` diagnostics.
- [x] Treat the existing `/mdtpm plan [pull]` command as the safe local preview path: it renders the exact validated marker plan without creating/updating macros or applying raid markers.
- [x] Document that preview path in the primary README so users do not need a hidden advanced command list to discover it.
- [x] Keep native AddOn Compartment integration and add the official localized **Dungeons & Raids** category metadata for the modern WoW AddOns list.
- [x] Keep all three automatic AddOn Compartment callbacks in `Core/AddonCompartment.lua`. `Core/Commands.lua` exposes `Addon.Commands` but does not define Compartment globals; the module load order only ensures the command API exists before the Compartment module consumes it.
- [x] Use the current `(addonName, menuButtonFrame)` automatic AddOn Compartment tooltip signature and anchor the tooltip to the actual menu frame.
- [x] Keep repository/runtime version text consistent with the TOC identity.
- [ ] Do **not** add scenario-forces auto-advancement in this pass. MDT Pull Marker owns deterministic marker execution, not a second route-progress estimator; expanding that boundary requires separate live evidence.
- [ ] Do **not** add Combat Log based pull inference. Existing readable/restricted death evidence and fail-closed progression remain the safer boundary.
- [ ] Do **not** add automatic route sharing/editing. MDT already owns those features.

## Result

The useful upgrade from the comparison is primarily discoverability, current WoW callback compatibility and drift resistance, not additional automation. The safe preview path and native WoW metadata are first-class, and the Compartment callbacks now have one explicit runtime owner instead of depending on a later file to overwrite an older callback implementation.
