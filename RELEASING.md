# Releasing MDT Pull Marker

`MDTPullMarker.toc` is the release identity and runtime inventory source of truth. Release archives are generated; they are not committed to `main`.

## Pre-release gate

1. Confirm the `## Version` in `MDTPullMarker.toc` is the intended version.
2. Confirm the current Retail interface number(s) and the current supported Mythic Dungeon Tools build.
3. Run the repository audit, Lua 5.1 regressions and deterministic package check. The GitHub workflows run these automatically.
4. Complete a live Retail smoke test: login/reload, configuration UI, route binding, route edits, grouped ownership, combat transition, Mythic+ challenge start/end, persistence and logout/login.
5. For CurseForge, upload the generated ZIP. Its archive root must be exactly `MDTPullMarker/`, with `MDTPullMarker/MDTPullMarker.toc` inside. Do not add a version to the root folder name.
6. Mark pre-release versions such as `-rcN` as Beta/preview distribution. Mark only live-accepted stable versions as Release.
7. Configure Mythic Dungeon Tools as a required project dependency on the distribution page.

## Tagged release

Push a signed/intentional tag named `v<VERSION>`, for example `v1.0.0-rc59`. `.github/workflows/release.yml` verifies that the tag exactly matches the TOC version, reruns source/regression checks, builds the archive twice, verifies byte-for-byte determinism, generates `SHA256SUMS.txt`, creates GitHub artifact provenance and creates a **draft** GitHub Release with the generated assets. Publish that draft only after the live Retail acceptance gate above has passed.

Do not commit generated ZIPs, checksums, build directories or local test output back to `main`.

## Distribution policy

The in-game addon must remain free, unobfuscated and publicly inspectable, must not contain advertising or donation solicitation, and must avoid unnecessary chat/network/disk/performance impact. Keep donation/support links, if any, on the project website rather than inside the addon UI.

Official references used by this repository:

- Blizzard WoW UI Add-On Development Policy: https://eu.forums.blizzard.com/en/wow/t/wow-user-interface-add-on-development-policy/1642
- CurseForge WoW archive processor rules: https://support.curseforge.com/support/solutions/articles/9000210425-curseforge-file-processor-rejections-and-how-to-solve-them
- CurseForge project/file release types: https://support.curseforge.com/support/solutions/articles/9000197242
- GitHub Actions secure-use guidance: https://docs.github.com/en/actions/reference/security/secure-use
- GitHub artifact attestations: https://docs.github.com/en/actions/concepts/security/artifact-attestations
