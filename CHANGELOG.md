# Changelog

> Repository evidence note: the current public tree contains the runtime source, focused Lua regression suite, repository/package audit scripts and checked-in GitHub validation workflows. Historical entries can describe verification assets from earlier development states; only assets that are present in the current tree are treated as current release evidence. The current automated gate compiles Lua 5.1, runs focused regressions, audits the repository/TOC inventory and verifies deterministic packaging.

## Unreleased

- No changes yet.

## 1.0.0-rc61 — public-distribution, protocol and SBOM hardening

- Add a deterministic SPDX 2.3 SBOM for the exact CurseForge runtime inventory, including source-file checksums, package verification code and the release ZIP digest.
- Build the ZIP and SBOM twice in CI and require byte-identical results before release.
- Publish the SBOM beside the release ZIP and checksum manifest, and bind the ZIP to the SBOM with a dedicated GitHub/Sigstore SBOM attestation in addition to ordinary build provenance.
- Lock Blizzard UI Add-On Development Policy hygiene for runtime/visible metadata by rejecting in-game advertising, premium, sponsorship and donation-solicitation tokens.
- Add a dedicated addon-message protocol audit for Blizzard's 16-byte prefix and 255-byte payload ceilings, the deliberately low ownership heartbeat cadence and the existing challenge/chat-lockdown send barrier; run it in both PR validation and tagged release validation.
- Move GitHub Actions Dependabot to weekly review and make CODEOWNERS explicit for its own policy, workflows, audit scripts, release metadata and runtime/integration trust boundaries.
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
