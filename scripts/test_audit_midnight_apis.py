#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT_PATH = ROOT / "scripts/audit_midnight_apis.py"

spec = importlib.util.spec_from_file_location("audit_midnight_apis", AUDIT_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def rejected(source: str) -> bool:
    return bool(module.runtime_policy_findings("fixture.lua", source))


def main() -> int:
    forbidden = {
        "combat log call": "CombatLogGetCurrentEventInfo()",
        "combat log event": 'RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")',
        "aura call": 'UnitAura("target", 1)',
        "namespaced aura": 'C_UnitAuras.GetAuraDataByIndex("target", 1)',
        "health": 'UnitHealth("target")',
        "power": 'UnitPower("target")',
        "cast": 'UnitCastingInfo("target")',
        "position": 'UnitPosition("target")',
        "spell automation": 'CastSpellByID(1)',
        "action automation": 'UseAction(1)',
        "target automation": 'TargetUnit("target")',
        "focus automation": 'FocusUnit("target")',
        "raid marker automation": 'SetRaidTarget("target", 8)',
        "ordinary chat automation": 'SendChatMessage("go", "PARTY")',
        "binding automation": 'SetBinding("CTRL-X", "SPELL Test")',
        "state driver": 'RegisterStateDriver(frame, "state", "[combat] 1; 0")',
        "secure handler": 'CreateFrame("Frame", nil, UIParent, "SecureHandlerAttributeTemplate")',
        "dynamic code": 'loadstring("return 1")()',
        "run script": 'RunScript("print(1)")',
    }
    for label, source in forbidden.items():
        assert rejected(source), f"policy fixture must be rejected: {label}"

    allowed = {
        "user secure button": 'CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")',
        "guarded addon message reference": 'C_ChatInfo.SendAddonMessage("MDTPM_OWNER", payload, "PARTY")',
        "supported death event": 'eventFrame:RegisterEvent("UNIT_DIED")',
    }
    for label, source in allowed.items():
        assert not rejected(source), f"policy fixture must remain allowed: {label}"

    print(f"ok - Midnight policy self-test passed ({len(forbidden)} forbidden, {len(allowed)} allowed fixtures)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
