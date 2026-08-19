#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MDTPullMarker.toc"
OWNERSHIP_PATH = "Runtime/MarkerOwnership.lua"
EVENTS_PATH = "Core/Events.lua"

# Combat-decision and automation surfaces that this addon must not consume.
# SecureActionButtonTemplate is intentionally not forbidden: MDTPullMarker uses a
# user-activated secure macro button and protects its attributes from combat-time
# mutation. The policy below focuses on executable API/event surfaces rather than
# documentation comments that may name a forbidden API to explain why it is not used.
FORBIDDEN_RUNTIME_PATTERNS: dict[str, re.Pattern[str]] = {
    "combat log decision feed": re.compile(r"\bCombatLogGetCurrentEventInfo\s*\("),
    "combat log event registration": re.compile(r"\bRegisterEvent\s*\(\s*['\"]COMBAT_LOG_EVENT_UNFILTERED['\"]\s*\)"),
    "aura decision feed": re.compile(r"\bUnitAura\s*\(|\bC_UnitAuras\s*[.:]"),
    "health/power decision feed": re.compile(r"\bUnitHealth(?:Max)?\s*\(|\bUnitPower(?:Max)?\s*\("),
    "cast decision feed": re.compile(r"\bUnitCastingInfo\s*\(|\bUnitChannelInfo\s*\("),
    "position decision feed": re.compile(r"\bUnitPosition\s*\(|\bGetPlayerMapPosition\s*\("),
    "protected spell/action automation": re.compile(r"\bCastSpellBy(?:ID|Name)\s*\(|\bUseAction\s*\("),
    "protected targeting automation": re.compile(r"\bTargetUnit\s*\(|\bFocusUnit\s*\("),
    "direct raid-marker automation": re.compile(r"\bSetRaidTarget\s*\("),
    "ordinary chat automation": re.compile(r"\bSendChatMessage\s*\("),
    "binding/state-driver automation": re.compile(r"\bSet(?:Override)?Binding\s*\(|\bRegisterStateDriver\s*\("),
    "dynamic code execution": re.compile(r"\bloadstring\s*\(|\bRunScript\s*\("),
}
FORBIDDEN_RUNTIME_PATTERNS["secure handler automation"] = re.compile(r"['\"][^'\"]*SecureHandler[^'\"]*['\"]")

# Midnight can suspend addon/chat messaging while an active challenge/encounter is
# running. MDTPullMarker legitimately uses a tiny pre-challenge ownership protocol,
# then freezes the owner and suspends messaging. Only the ownership implementation
# may touch the C_ChatInfo networking APIs. Core/Events.lua is separately audited as
# the single CHAT_MSG_ADDON dispatcher and must forward payloads directly to that
# ownership module without interpreting them as combat state.
NETWORK_API_REFERENCE = re.compile(
    r"\bC_ChatInfo\.(?:SendAddonMessage|RegisterAddonMessagePrefix|"
    r"IsAddonMessagePrefixRegistered|InChatMessagingLockdown)\b|\bSendAddonMessage\b"
)
REQUIRED_OWNERSHIP_GUARDS = {
    "chat lockdown guard": "C_ChatInfo.InChatMessagingLockdown",
    "active challenge guard": "C_ChallengeMode.GetActiveChallengeMapID",
    "frozen challenge owner": "state.challengeFrozen",
    "suspended communication result": '"comm-suspended"',
    "namespaced sender": "C_ChatInfo.SendAddonMessage",
    "namespaced prefix registration": "C_ChatInfo.RegisterAddonMessagePrefix",
    "bounded incoming payload": "safeString(message, 120)",
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


def runtime_policy_findings(rel: str, text: str) -> list[str]:
    findings: list[str] = []
    for label, pattern in FORBIDDEN_RUNTIME_PATTERNS.items():
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            findings.append(f"{rel}:{line}: forbidden {label}: {match.group(0).strip()}")
    return findings


def main() -> int:
    findings: list[str] = []
    runtime = toc_runtime_files()
    if not runtime:
        fail("TOC contains no Lua runtime files")

    ownership_text: str | None = None
    events_text: str | None = None
    for path in runtime:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT).as_posix()
        if rel == OWNERSHIP_PATH:
            ownership_text = text
        if rel == EVENTS_PATH:
            events_text = text

        findings.extend(runtime_policy_findings(rel, text))

        for match in NETWORK_API_REFERENCE.finditer(text):
            if rel == OWNERSHIP_PATH:
                continue
            line = text.count("\n", 0, match.start()) + 1
            findings.append(
                f"{rel}:{line}: addon messaging API is only allowed in {OWNERSHIP_PATH}: {match.group(0)}"
            )

        if "CHAT_MSG_ADDON" in text and rel != EVENTS_PATH:
            findings.append(f"{rel}: CHAT_MSG_ADDON may only be dispatched by {EVENTS_PATH}")

    if ownership_text is None:
        findings.append(f"{OWNERSHIP_PATH}: audited addon-messaging implementation is missing")
    else:
        for label, marker in REQUIRED_OWNERSHIP_GUARDS.items():
            if marker not in ownership_text:
                findings.append(f"{OWNERSHIP_PATH}: missing {label}: {marker}")
        if not re.search(
            r"if\s+state\.challengeFrozen\s+or\s+challengeActive\(\)\s+or\s+chatMessagingLockdown\(\)\s+then",
            ownership_text,
        ):
            findings.append(
                f"{OWNERSHIP_PATH}: sender must fail closed when challenge ownership is frozen, "
                "a challenge is active, or chat messaging is locked"
            )
        if not re.search(r"pcall\(C_ChatInfo\.SendAddonMessage\s*,", ownership_text):
            findings.append(f"{OWNERSHIP_PATH}: addon sender must remain protected by pcall")

    if events_text is None:
        findings.append(f"{EVENTS_PATH}: audited CHAT_MSG_ADDON dispatcher is missing")
    else:
        if events_text.count('"CHAT_MSG_ADDON"') != 2:
            findings.append(
                f"{EVENTS_PATH}: expected exactly one CHAT_MSG_ADDON handler and one registration"
            )
        if 'elseif event == "CHAT_MSG_ADDON" then\n    Addon.MarkerOwnership:OnAddonMessage(...)' not in events_text:
            findings.append(
                f"{EVENTS_PATH}: CHAT_MSG_ADDON must forward directly to MarkerOwnership:OnAddonMessage"
            )

    if findings:
        for finding in findings:
            print(f"::error::{finding}")
        fail("Midnight combat/API policy audit failed")

    print(
        f"ok - Midnight combat/API policy passed ({len(runtime)} runtime Lua files; "
        "guarded ownership messaging and dispatcher verified)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
