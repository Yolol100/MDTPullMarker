#!/usr/bin/env python3
"""Focused regression tests for the MDT upstream drift checker."""

from __future__ import annotations

import base64
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "check_upstream_drift.py"
SPEC = importlib.util.spec_from_file_location("check_upstream_drift", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

GOOD = "a" * 40
OTHER = "b" * 40
REQUIRED = sorted(module.REQUIRED_WATCH_PATHS)


def baseline() -> dict:
    return {
        "schemaVersion": 1,
        "reviewedAt": "2026-09-03",
        "provider": {
            "name": "MythicDungeonTools",
            "repository": "Nnoggie/MythicDungeonTools",
            "ref": "master",
            "expectedVersion": "6.2.12",
            "watchPaths": [{"path": path, "blobSha": GOOD} for path in REQUIRED],
        },
    }


def load_from(data: dict) -> dict:
    original = module.BASELINE_PATH
    try:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "baseline.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            module.BASELINE_PATH = path
            return module.load_baseline()
    finally:
        module.BASELINE_PATH = original


def encoded_changelog(version: str = "6.2.12") -> str:
    text = f"## {version} (2026-09-03)\n\n- fixture\n"
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def fake_api(path: str, _token: str | None) -> object:
    if "CHANGELOG.txt" in path:
        return {"sha": GOOD, "content": encoded_changelog()}
    return {"sha": GOOD}


def test_current_schema_requires_every_critical_surface() -> None:
    loaded = load_from(baseline())
    paths = {item["path"] for item in loaded["provider"]["watchPaths"]}
    assert paths == set(REQUIRED)


def test_missing_focus_marker_watch_is_rejected() -> None:
    data = baseline()
    data["provider"]["watchPaths"] = [
        item for item in data["provider"]["watchPaths"] if item["path"] != "Modules/FocusMarker.lua"
    ]
    try:
        load_from(data)
    except ValueError as exc:
        assert "Modules/FocusMarker.lua" in str(exc)
    else:
        raise AssertionError("missing FocusMarker watch path was accepted")


def test_matching_upstream_is_clean() -> None:
    original = module.api_get
    try:
        module.api_get = fake_api
        assert module.check_online(baseline()) == []
    finally:
        module.api_get = original


def test_focus_marker_drift_is_blocking() -> None:
    original = module.api_get

    def drift_api(path: str, token: str | None) -> object:
        result = fake_api(path, token)
        if "Modules/FocusMarker.lua" in path:
            return {"sha": OTHER}
        return result

    try:
        module.api_get = drift_api
        drift = module.check_online(baseline())
    finally:
        module.api_get = original
    assert len(drift) == 1
    assert "Modules/FocusMarker.lua" in drift[0]


def test_version_drift_is_blocking_even_when_watched_blobs_match() -> None:
    original = module.api_get

    def version_api(path: str, token: str | None) -> object:
        result = fake_api(path, token)
        if "CHANGELOG.txt" in path:
            return {"sha": GOOD, "content": encoded_changelog("6.2.13")}
        return result

    try:
        module.api_get = version_api
        drift = module.check_online(baseline())
    finally:
        module.api_get = original
    assert len(drift) == 1
    assert "MDT version changed" in drift[0]


if __name__ == "__main__":
    test_current_schema_requires_every_critical_surface()
    test_missing_focus_marker_watch_is_rejected()
    test_matching_upstream_is_clean()
    test_focus_marker_drift_is_blocking()
    test_version_drift_is_blocking_even_when_watched_blobs_match()
    print("ok - MDT upstream drift required-surface and online scenarios")
