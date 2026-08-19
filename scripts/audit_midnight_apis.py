#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MDTPullMarker.toc"

# Combat-decision and automation surfaces that this addon must not consume.
# SecureActionButtonTemplate is intentionally not forbidden: MDTPullMarker uses a
# user-activated secure macro button and protects its attributes from combat-time
# mutation. The policy below focuses on data/automation APIs that would let runtime
# code derive or execute combat decisions automatically.
FORBIDDEN_RUNTIME_PATTERNS: dict[str, re.Pattern[str]] = {
    "combat log decision feed": re.compile(r"\bCombatLogGetCurrentEventInfo\b|COMBAT_LOG_EVENT_UNFILTERED"),
    "aura decision feed": re.compile(r"\bUnitAura\b|\bC_UnitAuras\b"),
    "health/power decision feed": re.compile(r"\bUnitHealth(?:Max)?\b|\bUnitPower(?:Max)?\b"),
    "cast decision feed": re.compile(r"\bUnitCastingInfo\b|\bUnitChannelInfo\b"),
    "position decision feed": re.compile(r"\bUnitPosition\b|\bGetPlayerMapPosition\b"),
    "protected spell/action automation": re.compile(r"\bCastSpellBy(?:ID|Name)\b|\bUseAction\b"),
    "protected targeting automation": re.compile(r"\bTargetUnit\b|\bFocusUnit\b"),
    "binding/state-driver automation": re.compile(r"\bSet(?:Override)?Binding\b|\bRegisterStateDriver\b"),
    "addon networking": re.compile(r"\bSendAddonMessage\b|\bC_ChatInfo\.SendAddonMessage\b"),
    "dynamic code execution": re.compile(r"\bloadstring\b|\bRunScript\b"),
}


def fail(message: str) -> None:
    print(f"error - {message}", file=sys.stderr)
    raise SystemExit(1)


def toc_runtime_files() -> list[Path]:
    files: list[Path] = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        path = ROOT / line.replace("\\", "/")
        if path.suffix.lower() == ".lua":
            files.append(path)
    return files


def main() -> int:
    findings: list[str] = []
    runtime = toc_runtime_files()
    if not runtime:
        fail("TOC contains no Lua runtime files")

    for path in runtime:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT).as_posix()
        for label, pattern in FORBIDDEN_RUNTIME_PATTERNS.items():
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{rel}:{line}: forbidden {label}: {match.group(0)}")

    if findings:
        for finding in findings:
            print(f"::error::{finding}")
        fail("Midnight combat/API policy audit failed")

    print(f"ok - Midnight combat/API policy passed ({len(runtime)} runtime Lua files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
