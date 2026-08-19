# Releasing MDT Pull Marker

`MDTPullMarker.toc` is the release identity and runtime inventory source of truth. Release archives are generated; they are not committed to `main`.

## Pre-release gate

1. Confirm the `## Version` in `MDTPullMarker.toc` is the intended version.
2. Confirm the current Retail interface number(s) and the current supported Mythic Dungeon Tools build.
3. Run the repository audit, Midnight combat/API policy audit, upstream-baseline validation, Lua 5.1 regressions, blocking Luacheck and deterministic package check. The GitHub workflows run these automatically.
4. Complete `LIVE_TEST_MATRIX.md` against the exact packaged build. This includes login/reload, MDT integration and route identity, grouped ownership, addon-message lockdown, secure marking/macro limits, combat transition, Mythic+ challenge start/end, death evidence, persistence, taint/errors and performance.
5. Record the tested WoW build/interface, addon version, MDT version and packaged ZIP SHA-256. CI/source review alone may be labelled PASS-CI, never PASS-LIVE.
6. For CurseForge, upload the generated ZIP. Its archive root must be exactly `MDTPullMarker/`, with `MDTPullMarker/MDTPullMarker.toc` inside. Do not add a version to the root folder name.
7. Mark pre-release versions such as `-rcN` as Beta/preview distribution. Mark only live-accepted stable versions as Release.
8. Configure Mythic Dungeon Tools as a required project dependency on the distribution page.

## Tagged release

Push a signed/intentional tag named `v<VERSION>`, for example `v1.0.0-rc59`. `.github/workflows/release.yml` verifies that the tag exactly matches the TOC version, reruns the same repository/Midnight/upstream/Luacheck/regression gates used before merge, builds the archive twice, verifies byte-for-byte determinism, generates `SHA256SUMS.txt`, creates GitHub artifact provenance and creates a **draft** GitHub Release with the generated assets. Publish that draft only after `LIVE_TEST_MATRIX.md` has passed on the exact artifact.

Do not commit generated ZIPs, checksums, build directories or local test output back to `main`.

## Distribution policy

The in-game addon must remain free, unobfuscated and publicly inspectable, must not contain advertising or donation solicitation, and must avoid unnecessary chat/network/disk/performance impact. Keep donation/support links, if any, on the project website rather than inside the addon UI.

Official references used by this repository:

- Blizzard WoW UI Add-On Development Policy: https://eu.forums.blizzard.com/en/wow/t/wow-user-interface-add-on-development-policy/1642
- Blizzard Midnight combat-addon direction and interface changes: https://worldofwarcraft.blizzard.com/news
- CurseForge WoW archive processor rules: https://support.curseforge.com/support/solutions/articles/9000210425-curseforge-file-processor-rejections-and-how-to-solve-them
- CurseForge project/file release types: https://support.curseforge.com/support/solutions/articles/9000197242
- GitHub Actions secure-use guidance: https://docs.github.com/en/actions/reference/security/secure-use
- GitHub artifact attestations: https://docs.github.com/en/actions/concepts/security/artifact-attestations
