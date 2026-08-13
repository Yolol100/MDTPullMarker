# Changelog

## 1.0.0-rc58 — software-assurance closure and pre-combat route safety

- Closed the remaining pre-combat stale-route window by synchronously parking managed execution on MDT enemy/pull mutation interactions outside combat; the 250 ms route watcher is now fallback detection rather than the primary safety barrier.
- Freeze the validated execution contract when a route-changing interaction occurs during combat and force an out-of-combat invalidation/rebuild before execution resumes.
- Added pre-sort scan, unique-key and aggregate budgets to route/clone/assignment identity collection so oversized or adversarial tables fail closed before unbounded sort/allocation work.
- Made display/log clipping UTF-8 code-point safe while keeping external identifiers exact/reject-on-overlength.
- Added executable resource, property/determinism, pinned MDT 6.1.20/6.2.1 compatibility and mutation-regression suites; five previously surviving safety mutants are now required to be killed.
- Added a localization boundary with `Locale/enUS.lua` for normal user-facing UI/binding/tooltip strings and documented the localization contract for contributors.
- Added bidirectional traceability, an SFMEA-style hazard register, security policy and dependency/provenance documentation.
- Added a cryptographically pinned Lua Language Server workspace-diagnostic gate to CI, while preserving Lua 5.1 as the canonical language-runtime gate.
- Made runtime/source ZIPs reproducible across clean checkouts by fixing archive timestamps, permissions and ordering; package verification rejects duplicate members, unexpected roots/inventory, unsafe paths and source symlinks.
- Expanded route mutation watching across bound and legacy/current-route mode and fail closed when previously readable route data disappears.
- Bounded persisted diagnostics, closed schema-12 normalization to an allowlist, sanitized migration backups, blocked future-schema execution, and required an explicit positive death verdict for automatic pull completion.
- Pinned CI to Ubuntu 24.04 with read-only contents permissions and a reviewed checkout commit.
- Updated architecture/safety/live-test/release verification documentation and bumped runtime/package identity to `1.0.0-rc58`.

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
