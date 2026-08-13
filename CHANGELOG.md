# Changelog

## 1.0.0-rc57 — overlooked release-integrity and stale-route hardening

- Made runtime/source ZIPs genuinely reproducible across clean checkouts by fixing archive timestamps, permissions and ordering and using stored payloads so hashes do not depend on source mtimes or a particular DEFLATE implementation.
- Hardened package verification against duplicate members, extra roots/inventory, unsafe paths and symlinked source entries; added an mtime-divergence reproducibility regression.
- Expanded the MDT route watcher from bound routes to legacy/current-route mode and included membership fingerprints even for stable UID routes.
- Replaced full snapshot normalization inside the 250 ms watcher with a bounded route-v3-compatible membership signature to avoid recurring large temporary allocations.
- Treat loss of previously readable MDT route data as a fail-closed transition that parks managed execution before rebuild/recovery.
- Bounded persisted diagnostic log level/message strings immediately to the database validator limits.
- Made schema-12 normalization a closed allowlist on every initialization/transaction, so unknown legacy/foreign top-level fields cannot survive an extra SavedVariables write.
- Sanitized archival migration backups through bounded deep copies; corrupt/cyclic backup payloads are discarded without disabling healthy active state.
- Closed a death-progression gap: restricted/unknown death identity no longer counts as permission to auto-complete; only an explicit `true` completion verdict advances automatically.
- Propagated `future-schema` database blocking into marker-plan construction so downgrade safety cannot fall through to legacy/current-route execution on memory defaults.
- Made the canonical verification script require a real Lua 5.1 interpreter and label any explicit newer-Lua fallback as non-certifying.
- Removed the unproven StyLua release gate from CI until a separately reviewed formatting-only baseline exists; CI now runs the same canonical Lua 5.1 + regressions + package oracle as contributors.
- Pinned CI to Ubuntu 24.04, reduced workflow permissions to read-only contents and pinned the sole checkout action to its reviewed v4.2.2 commit; Python uses the runner OS instead of another floating setup action.
- Updated the live-test matrix for legacy/current-route mutation, UID membership mutation and route-data loss/recovery.

## 1.0.0-rc56 — MAP safety, architecture and verification hardening

- Added synchronous execution invalidation and verified parking of addon-managed smart/route macros before delayed session or MDT route rebuilds.
- Added an out-of-combat bound-route signature watcher so pull-membership and marker-assignment mutations are detected even when MDT exposes no dedicated mutation callback.
- Made UID-less route bindings strict by saved membership fingerprint; a different unique same-name route can no longer silently take over a binding.
- Split combat-log uncertainty into generic tracking failures versus genuinely restricted death evidence. Reader failures, unavailable APIs and secret event types now block completion; only a proven death event with restricted destination identity remains advisory.
- Centralized communication failure handling so missing/failed `SendAddonMessage`, channel uncertainty and registration failures clear grouped ownership immediately.
- Added an rc52+ owner-protocol compatibility gate. A current client remains passive when it discovers an incompatible pre-rc52 peer, closing the deterministic-priority mixed-version split-brain case.
- Added synchronous dungeon/session invalidation before ownership refresh on world transitions.
- Added `DataUtils.ValidatedString` and switched persisted route identifiers to reject overlength values instead of silently truncating identity.
- Renamed `Runtime/PullController.lua` → `Runtime/RuntimeController.lua`, `UI/Configuration.lua` → `UI/ConfigurationUI.lua`, and `Integrations/MDTUI.lua` → `Integrations/MDTIntegration.lua` so file names match public module names.
- Added LuaCATS model declarations, `.luarc.json`, `.stylua.toml`, GitHub Actions CI, executable Lua regression tests, static repository contracts, deterministic package verification and architecture/safety/live-test documentation.
- Bumped runtime, TOC and documentation identity to `1.0.0-rc56`.

## 1.0.0-rc55 — communication recovery + current combat-log reader

- Reworked addon-prefix recovery so an already registered Retail prefix is independently recognized instead of being stranded by `DuplicatePrefix`.
- Preferred `C_CombatLog.GetCurrentEventInfo` directly, with the deprecated global retained only as compatibility fallback.
- Updated runtime, TOC, README and compatibility identity to rc55.

## 1.0.0-rc54 — bounded creature-name cache + completion hardening

- Bounded localized creature-name caching to 4,096 entries.
- Hardened completion handling around asynchronous callbacks and zero readable death evidence.

Earlier release history is intentionally not re-expanded in this locally materialized modernization package. The original repository at source commit `90df33a78e43baeab461d6a54e8981d50683d4f3` remains the provenance source for the full pre-rc54 historical changelog.
