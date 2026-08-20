# Changelog

> Repository evidence note: the current public tree contains the runtime source, focused Lua regression suite, repository/package audit scripts and checked-in GitHub validation workflows. Historical entries can describe verification assets from earlier development states; only assets that are present in the current tree are treated as current release evidence. The current automated gate compiles Lua 5.1, runs focused regressions, audits the repository/TOC inventory and verifies deterministic packaging.

## Unreleased

- No changes yet.

## 1.0.0-rc61 — public-distribution and SBOM hardening

- Add a deterministic SPDX 2.3 SBOM for the exact CurseForge runtime inventory, including source-file checksums, package verification code and the release ZIP digest.
- Build the ZIP and SBOM twice in CI and require byte-identical results before release.
- Publish the SBOM beside the release ZIP and checksum manifest, and bind the ZIP to the SBOM with a dedicated GitHub/Sigstore SBOM attestation in addition to ordinary build provenance.
- Lock Blizzard UI Add-On Development Policy hygiene for runtime/visible metadata by rejecting in-game advertising, premium, sponsorship and donation-solicitation tokens.
- Declare the existing MIT license in TOC metadata and retain the case-sensitive single-root `MDTPullMarker/MDTPullMarker.toc` CurseForge package contract.
- Re-verify Mythic Dungeon Tools upstream on 2026-08-20; master remains release 6.2.4, so no MDT runtime adapter change is required.

## 1.0.0-rc60 — ownership transport error hardening

- Reject secret, non-string, empty and overlong ownership protocol payloads before parsing; incoming `CHAT_MSG_ADDON` data is no longer coerced through `tostring` at the ownership trust boundary.
- Add deterministic malformed-input coverage for wrong prefixes/channels, self messages, non-string and secret payloads, payload-size limits, invalid eligibility and out-of-range protocol versions.
- Preserve the existing pre-challenge ownership election, active-challenge freeze, messaging-lockdown and split-brain fail-closed contracts while assigning the runtime behavior change a new immutable RC identity.

## 1.0.0-rc59 — Midnight Season 2 readiness

- Replaced the restricted Midnight `COMBAT_LOG_EVENT_UNFILTERED` registration with the supported `UNIT_DIED` event and retained fail-closed handling for secret unit GUIDs.
- Restricted grouped marker-owner candidates to eligible clients that actually announced a compatible owner protocol, so a tank or leader without MDT Pull Marker cannot suppress execution.
- Freeze the settled marker owner for the complete active Mythic+ challenge and suppress ownership heartbeats/re-election while Midnight addon messaging is locked down.
- Fail closed if the frozen challenge owner is positively proven to have left the group; unknown/secret roster reads preserve the freeze instead of risking split-brain.
- Added deterministic coverage for challenge start during the short ownership settle window; an unsettled election remains passive for that challenge instead of freezing a provisional owner.
- Kept automatic bulk marker application at Blizzard's Season 2 limit of three target-marker operations per macro activation and added an explicit boundary regression.
- Reviewed the adapter against upstream Mythic Dungeon Tools 6.2.4; Season 2 enemy-force corrections remain owned by MDT instead of being duplicated in this add-on.
- Added focused Lua 5.1 regression coverage for the event inventory, readable/restricted unit-death evidence, grouped ownership election and Midnight challenge-lockdown behavior.
- Added `SECURITY.md` and `CODEOWNERS` repository maintenance metadata.
- Bumped runtime/package identity to `1.0.0-rc59`.

## 1.0.0-rc58 — pre-combat route safety and repository cleanup

- Closed the remaining pre-combat stale-route window by synchronously parking managed execution on MDT enemy/pull mutation interactions outside combat; the 250 ms route watcher is fallback detection rather than the primary safety barrier.
- Freeze the validated execution contract when a route-changing interaction occurs during combat and force an out-of-combat invalidation/rebuild before execution resumes.
- Added pre-sort scan, unique-key and aggregate budgets to route/clone/assignment identity collection so oversized or adversarial tables fail closed before unbounded sort/allocation work.
- Made display/log clipping UTF-8 code-point safe while keeping external identifiers exact/reject-on-overlength.
- Added a localization boundary with `Locale/enUS.lua` for normal user-facing UI, binding and tooltip strings.
- Expanded route mutation watching across bound and legacy/current-route mode and fail closed when previously readable route data disappears.
- Bounded persisted diagnostics, closed schema-12 normalization to an allowlist, sanitized migration backups, blocked future-schema execution, and required an explicit positive death verdict for automatic pull completion.
- The rc58 repository gate compiled all Lua with Lua 5.1 and verified every active TOC path; current repository assurance has since expanded as described in the evidence note above.
- Bumped runtime, TOC and documentation identity to `1.0.0-rc58`.

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
- Historical rc56 development included additional static/test/package assurance work; see the repository evidence note above when interpreting those historical claims against the current tree.
- Bumped runtime, TOC and documentation identity to rc56.

## 1.0.0-rc55 — communication recovery + current combat-log reader

- Reworked addon-prefix recovery so an already registered Retail prefix is independently recognized instead of being stranded by `DuplicatePrefix`.
- Preferred `C_CombatLog.GetCurrentEventInfo` directly, with the deprecated global retained only as compatibility fallback.
- Updated runtime, TOC, README and compatibility identity to rc55.

## 1.0.0-rc54 — bounded creature-name cache + completion hardening

- Bounded localized creature-name caching to 4,096 entries.
- Hardened completion handling around asynchronous callbacks and zero readable death evidence.

Earlier release history is intentionally not re-expanded in this modernization package. The original repository at source commit `90df33a78e43baeab461d6a54e8981d50683d4f3` remains the provenance source for the full pre-rc54 historical changelog.
