#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE_PATH = ROOT / "UPSTREAM_BASELINE.json"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
API = "https://api.github.com"
REQUIRED_WATCH_PATHS = {
    "CHANGELOG.txt",
    "Modules/API.lua",
    "Modules/FocusMarker.lua",
    "Modules/Presets.lua",
    "Core/Bootstrap.lua",
    "MythicDungeonTools_UI/Bootstrap.lua",
}


def fail(message: str) -> None:
    raise ValueError(message)


def load_baseline() -> dict:
    try:
        data = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {BASELINE_PATH.name}: {exc}")

    if data.get("schemaVersion") != 1:
        fail("schemaVersion must be 1")
    if not DATE_RE.fullmatch(str(data.get("reviewedAt", ""))):
        fail("reviewedAt must be YYYY-MM-DD")

    provider = data.get("provider")
    if not isinstance(provider, dict):
        fail("provider must be an object")
    if provider.get("name") != "MythicDungeonTools":
        fail("provider.name must be MythicDungeonTools")
    repository = provider.get("repository")
    if not isinstance(repository, str) or repository.count("/") != 1:
        fail("provider.repository must be owner/name")
    if not isinstance(provider.get("ref"), str) or not provider["ref"].strip():
        fail("provider.ref is required")
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(provider.get("expectedVersion", ""))):
        fail("provider.expectedVersion must be x.y.z")

    watches = provider.get("watchPaths")
    if not isinstance(watches, list) or not watches:
        fail("provider.watchPaths must be non-empty")
    seen: set[str] = set()
    for watch in watches:
        if not isinstance(watch, dict):
            fail("watch entries must be objects")
        path = watch.get("path")
        blob_sha = watch.get("blobSha")
        if not isinstance(path, str) or not path or path.startswith("/") or ".." in Path(path).parts:
            fail(f"invalid watch path: {path!r}")
        if path in seen:
            fail(f"duplicate watch path: {path}")
        seen.add(path)
        if not isinstance(blob_sha, str) or not SHA_RE.fullmatch(blob_sha):
            fail(f"invalid blobSha for {path}")

    missing_required = sorted(REQUIRED_WATCH_PATHS - seen)
    if missing_required:
        fail("provider.watchPaths missing required compatibility paths: " + ", ".join(missing_required))
    return data


def api_get(path: str, token: str | None) -> object:
    request = urllib.request.Request(
        API + path,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "MDTPullMarker-upstream-audit",
            "X-GitHub-Api-Version": "2022-11-28",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"GitHub API request failed for {path}: {exc}") from exc


def check_online(data: dict) -> list[str]:
    token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
    provider = data["provider"]
    repo = provider["repository"]
    ref = provider["ref"]
    drift: list[str] = []

    for watch in provider["watchPaths"]:
        quoted_path = urllib.parse.quote(watch["path"], safe="/")
        quoted_ref = urllib.parse.quote(ref, safe="")
        payload = api_get(f"/repos/{repo}/contents/{quoted_path}?ref={quoted_ref}", token)
        actual_sha = payload.get("sha") if isinstance(payload, dict) else None
        if actual_sha != watch["blobSha"]:
            drift.append(
                f"watched MDT file changed: {ref}:{watch['path']} expected "
                f"{watch['blobSha'][:12]}, got {str(actual_sha)[:12]}"
            )

    changelog = api_get(
        f"/repos/{repo}/contents/CHANGELOG.txt?ref={urllib.parse.quote(ref, safe='')}", token
    )
    if isinstance(changelog, dict):
        import base64

        raw = changelog.get("content")
        if isinstance(raw, str):
            try:
                text = base64.b64decode(raw).decode("utf-8")
            except (ValueError, UnicodeDecodeError):
                text = ""
            expected = f"## {provider['expectedVersion']} ("
            if not text.startswith(expected):
                drift.append(
                    f"MDT version changed: expected changelog to start with {expected!r}"
                )
    return drift


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--validate-only", action="store_true")
    mode.add_argument("--online", action="store_true")
    args = parser.parse_args()

    try:
        data = load_baseline()
    except ValueError as exc:
        print(f"error - {exc}", file=sys.stderr)
        return 2

    provider = data["provider"]
    print(
        f"ok - upstream baseline valid ({provider['name']} {provider['expectedVersion']}, "
        f"reviewed {data['reviewedAt']})"
    )
    if not args.online:
        return 0

    try:
        drift = check_online(data)
    except RuntimeError as exc:
        print(f"error - {exc}", file=sys.stderr)
        return 2

    if drift:
        for message in drift:
            print(f"::error::{message}")
        print("error - MDT upstream drift detected; re-review compatibility before updating the baseline", file=sys.stderr)
        return 1

    print("ok - no watched MDT upstream drift detected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
