#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Runtime/MarkerOwnership.lua"
TOC = ROOT / "MDTPullMarker.toc"
MAX_PREFIX_BYTES = 16
MAX_MESSAGE_BYTES = 255


def fail(message: str) -> None:
    raise SystemExit(f"error - {message}")


def main() -> int:
    source = SOURCE.read_text(encoding="utf-8")
    toc = TOC.read_text(encoding="utf-8")

    prefix_match = re.search(r'^local PREFIX = "([^"]+)"$', source, re.M)
    if not prefix_match:
        fail("ownership addon-message prefix is not a fixed literal")
    prefix = prefix_match.group(1)
    if len(prefix.encode("utf-8")) > MAX_PREFIX_BYTES:
        fail(f"addon-message prefix exceeds {MAX_PREFIX_BYTES} bytes")

    heartbeat = re.search(r"^local HEARTBEAT_SECONDS = ([0-9.]+)$", source, re.M)
    if not heartbeat or float(heartbeat.group(1)) < 1.0:
        fail("ownership heartbeat is too aggressive for low-volume addon messaging")

    version_match = re.search(r"^## Version:\s*(\S+)\s*$", toc, re.M)
    if not version_match:
        fail("TOC version is missing")
    version = version_match.group(1)
    if not re.fullmatch(r"1\.0\.0-rc\d+", version):
        fail(f"unexpected release version format: {version}")

    # Wire format is KIND|VERSION|ELIGIBLE|PROTOCOL. KIND and ELIGIBLE are one
    # byte each; protocol is constrained to 1..255 on receive. Prove the current
    # canonical release identity cannot approach WoW's 255-byte message ceiling.
    worst_case_payload = f"H|{version}|1|255"
    if len(worst_case_payload.encode("utf-8")) > MAX_MESSAGE_BYTES:
        fail("ownership wire payload can exceed the WoW addon-message ceiling")

    required = (
        'C_ChatInfo.RegisterAddonMessagePrefix, PREFIX',
        'C_ChatInfo.SendAddonMessage, PREFIX, payload, channel',
        'if state.challengeFrozen or challengeActive() or chatMessagingLockdown() then',
        'return false, "comm-suspended"',
        'local rawMessage = safeString(message, 120)',
    )
    for marker in required:
        if marker not in source:
            fail(f"ownership network safety marker missing: {marker}")

    dependabot = (ROOT / ".github/dependabot.yml").read_text(encoding="utf-8")
    if "package-ecosystem: github-actions" not in dependabot or "interval: weekly" not in dependabot:
        fail("GitHub Actions Dependabot must remain enabled on a weekly cadence")

    owners = (ROOT / ".github/CODEOWNERS").read_text(encoding="utf-8")
    for marker in (
        "/.github/CODEOWNERS @Yolol100",
        "/.github/dependabot.yml @Yolol100",
        "/.github/workflows/ @Yolol100",
        "/scripts/ @Yolol100",
        "/Runtime/ @Yolol100",
        "/Integrations/ @Yolol100",
        "/MDTPullMarker.toc @Yolol100",
    ):
        if marker not in owners:
            fail(f"critical CODEOWNER boundary missing: {marker}")

    dependency_review = (ROOT / ".github/workflows/dependency-review.yml").read_text(encoding="utf-8")
    if "actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294" not in dependency_review:
        fail("Dependency Review Action must remain pinned to the reviewed v5.0.0 commit")
    if "fail-on-severity: moderate" not in dependency_review:
        fail("Dependency Review must block newly introduced moderate-or-higher vulnerabilities")
    if "persist-credentials: false" not in dependency_review:
        fail("Dependency Review checkout must not persist Git credentials")

    print(
        "ok - addon-message protocol and repository dependency governance are "
        "bounded, lockdown-aware and release-enforced"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
