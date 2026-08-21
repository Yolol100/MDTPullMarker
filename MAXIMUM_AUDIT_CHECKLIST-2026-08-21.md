# Maximum release audit checklist — 2026-08-21

This checklist records the cross-project release audit used for same-day readiness. A source/CI pass is not a substitute for live Retail evidence.

## Evidence states

- `PASS-SOURCE`: verified from current source/configuration.
- `PASS-CI`: verified by the exact tested Git tree in CI.
- `PASS-ONLINE`: verified against a current external source on the audit date.
- `PASS-LIVE`: reproduced in the target Retail client/platform.
- `MANUAL`: requires target-runtime evidence.
- `N/A`: not applicable to this project.
- `FAIL`: confirmed defect/blocker.

## Master domains

1. Product scope and user workflow are explicit.
2. Version, TOC/interface and release identity are consistent.
3. Package inventory and load order are deterministic.
4. Current WoW 12.1 API use is compatible and fail-safe.
5. Secret/restricted values cannot influence unsupported decisions.
6. Combat/protected-action boundaries match Blizzard policy.
7. Chat/addon-network surfaces are minimal, bounded and lockdown-safe.
8. External addon/provider dependencies are current and optional/required exactly as documented.
9. Provider callback contracts are checked against current upstream releases.
10. Encounter/dungeon data avoids stale duplicate truth and volatile hard-coding.
11. Unsupported, ambiguous, stale or malformed context fails closed.
12. SavedVariables/config migration and corruption paths are bounded.
13. UI, localization and accessibility behavior are explicitly tested.
14. Taint, CPU/frame-time, memory and repeated-use behavior have live gates.
15. Reload/reconnect/wipe/reset and other lifecycle failures are covered.
16. Repository secret/binary/path/security hygiene is machine-audited.
17. GitHub Actions use least privilege, immutable pins and safe triggers.
18. Dependencies are pinned/audited where the project has external runtime packages.
19. Release artifacts have an SBOM where applicable.
20. Builds are deterministic/reproducible from the tested source.
21. Provenance/attestation/signing is isolated to the correct release boundary.
22. Version/tag/release immutability prevents replacing a published identity.
23. Branch/ruleset/security-admin state is tracked separately from source claims.
24. Distribution metadata/channel/dependency/license claims match evidence.
25. Current external sources are rechecked on the day of a readiness claim.
26. Live acceptance records the exact installed version/SHA and environment.
27. Rollback/recovery remains possible from a prior verified artifact/version.
28. Final GO/NO-GO distinguishes source readiness from target-runtime readiness.

MDT Pull Marker-specific detailed checks remain enforced by repository audits, focused Lua regressions, deterministic package/SPDX generation and `LIVE_TEST_MATRIX.md`.
