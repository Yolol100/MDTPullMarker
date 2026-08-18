# Contributing to MDT Pull Marker

Thank you for helping improve MDT Pull Marker. Changes should keep the addon small, inspectable, deterministic to package and safe under World of Warcraft Retail restrictions.

## Source rules

- `MDTPullMarker.toc` is the runtime inventory source of truth. Do not add duplicate, retired or alternate runtime implementations outside that inventory.
- Keep runtime code compatible with Lua 5.1 and the supported Retail interface contract.
- Keep Mythic Dungeon Tools integration behind the existing integration boundary. Do not copy MDT dungeon/forces data into this repository.
- Do not add obfuscation, advertising, in-game donation solicitation, telemetry, secrets or generated release archives to the addon source.
- Do not commit build output, caches, logs, local configuration, private keys or signing material.

## Validation before a pull request

Run the same core checks used by CI:

```bash
python3 -m py_compile scripts/audit_repository.py scripts/build_release.py
python3 scripts/audit_repository.py
lua5.1 tests/run.lua
python3 scripts/build_release.py /tmp/MDTPullMarker-test.zip
git diff --check
```

Changes that affect grouped ownership, combat behavior, macros, route binding, persistence or UI behavior should include or update focused regression coverage. State any live Retail testing that was performed; do not mark live-client behavior as verified if it was not tested in the game client.

## Pull request expectations

- Explain the user-visible or reliability problem and the chosen fix.
- Keep unrelated cleanup out of the same change when possible.
- Leave `## Version` unchanged unless the change is intentionally preparing a new release identity.
- Do not attach or commit generated ZIPs. Tagged release assets are built by GitHub Actions.
- Call out compatibility impact for Retail, Mythic Dungeon Tools and saved variables when relevant.

Security vulnerabilities should be reported using `SECURITY.md`, not a public issue.

## Release changes

Follow `RELEASING.md`. A release tag creates a draft release only; publishing remains gated on the documented live Retail acceptance checks.
