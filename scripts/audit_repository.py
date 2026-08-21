#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
import unicodedata
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MDTPullMarker.toc"
MAX_TRACKED_BYTES = 1024 * 1024
RETIRED_PATHS = {
    "Integrations/MDTUI.lua",
    "Runtime/PullController.lua",
    "UI/Configuration.lua",
}
REQUIRED_REPOSITORY_FILES = {
    ".editorconfig",
    ".gitattributes",
    ".gitignore",
    ".github/CODEOWNERS",
    ".github/dependabot.yml",
    ".github/workflows/regression.yml",
    ".github/workflows/release.yml",
    ".github/workflows/upstream-drift.yml",
    ".github/workflows/validate.yml",
    ".luacheckrc",
    "COMPATIBILITY.md",
    "LICENSE",
    "LIVE_TEST_MATRIX.md",
    "README.md",
    "RELEASING.md",
    "SECURITY.md",
    "UPSTREAM_BASELINE.json",
    "scripts/audit_addon_network.py",
    "scripts/audit_midnight_apis.py",
    "scripts/test_audit_midnight_apis.py",
    "scripts/audit_repository.py",
    "scripts/build_release.py",
    "scripts/build_sbom.py",
    "scripts/check_upstream_drift.py",
    "tests/run.lua",
}
FORBIDDEN_PATH_PARTS = {
    ".idea",
    ".vscode",
    "__pycache__",
    ".pytest_cache",
    "node_modules",
    "dist",
    "build",
    "coverage",
    ".env",
}
FORBIDDEN_SUFFIXES = {
    ".log",
    ".tmp",
    ".swp",
    ".swo",
    ".bak",
    ".orig",
    ".rej",
    ".pem",
    ".p12",
    ".pfx",
    ".zip",
    ".exe",
}
SECRET_PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    "Slack token": re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{20,}\b"),
    "OpenAI key": re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}\b"),
}
FORBIDDEN_ADDON_POLICY = re.compile(
    r"\b(?:patreon|paypal|donat(?:e|ion|ions)|premium|advertis(?:e|ement|ements|ing)|sponsor(?:ed|ship)?)\b",
    re.I,
)


def fail(message: str) -> None:
    print(f"error - {message}", file=sys.stderr)
    raise SystemExit(1)


def git_files() -> list[str]:
    raw = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    return [item.decode("utf-8") for item in raw.split(b"\0") if item]


def read_text(rel: str) -> str:
    data = (ROOT / rel).read_bytes()
    if b"\0" in data:
        fail(f"binary/NUL content is not allowed in source repository: {rel}")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        fail(f"tracked source must be UTF-8: {rel}")
    if "\r" in text:
        fail(f"tracked source must use LF line endings: {rel}")
    if data and not data.endswith(b"\n"):
        fail(f"tracked text must end with a newline: {rel}")
    if len(data) > MAX_TRACKED_BYTES:
        fail(f"tracked source exceeds {MAX_TRACKED_BYTES} bytes: {rel}")
    return text


def toc_entries() -> list[str]:
    entries: list[str] = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            entries.append(line.replace("\\", "/"))
    return entries


def validate_addon_policy(entries: list[str]) -> None:
    metadata = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        if raw.startswith(("## Title:", "## Notes:", "## Category:", "## X-Category:")):
            metadata.append(raw)
    visible = "\n".join(metadata)
    if FORBIDDEN_ADDON_POLICY.search(visible):
        fail("Blizzard add-on policy advertising/donation/premium token in visible TOC metadata")
    for rel in entries:
        source = read_text(rel)
        match = FORBIDDEN_ADDON_POLICY.search(source)
        if match:
            fail(f"Blizzard add-on policy advertising/donation/premium token in runtime {rel}: {match.group(0)}")


def main() -> int:
    files = git_files()
    if not files:
        fail("repository contains no tracked files")

    missing_required = sorted(REQUIRED_REPOSITORY_FILES - set(files))
    if missing_required:
        fail("required repository metadata/audit contract is missing: " + ", ".join(missing_required))
    retired = sorted(RETIRED_PATHS & set(files))
    if retired:
        fail("retired duplicate source paths must stay deleted: " + ", ".join(retired))

    seen: dict[str, str] = {}
    for rel in files:
        if unicodedata.normalize("NFC", rel) != rel:
            fail(f"path is not NFC-normalized: {rel}")
        path = PurePosixPath(rel)
        if path.is_absolute() or ".." in path.parts or any(part in FORBIDDEN_PATH_PARTS for part in path.parts):
            fail(f"forbidden tracked path: {rel}")
        if path.suffix.lower() in FORBIDDEN_SUFFIXES or rel.endswith("~"):
            fail(f"generated/temporary/sensitive file must not be tracked: {rel}")
        key = rel.casefold()
        if key in seen and seen[key] != rel:
            fail(f"case-colliding tracked paths: {seen[key]} / {rel}")
        seen[key] = rel
        if (ROOT / rel).is_symlink():
            fail(f"symlinks are not allowed: {rel}")
        text = read_text(rel)
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(text):
                fail(f"possible {label} committed in {rel}")

    entries = toc_entries()
    if not entries:
        fail("TOC contains no runtime files")
    if len(entries) != len(set(entries)):
        fail("TOC contains duplicate runtime entries")
    for rel in entries:
        if rel not in files:
            fail(f"TOC runtime file is missing/untracked: {rel}")

    runtime_lua = {rel for rel in files if rel.endswith(".lua") and not rel.startswith("tests/")}
    unlisted = sorted(runtime_lua - set(entries))
    if unlisted:
        fail("runtime Lua exists outside TOC inventory: " + ", ".join(unlisted))
    validate_addon_policy(entries)

    for rel in files:
        if rel.startswith(".github/workflows/") and rel.endswith((".yml", ".yaml")):
            text = read_text(rel)
            if "permissions:" not in text:
                fail(f"workflow must declare permissions explicitly: {rel}")
            for forbidden_trigger in ("pull_request_target:", "repository_dispatch:", "workflow_run:"):
                if forbidden_trigger in text:
                    fail(f"high-risk workflow trigger {forbidden_trigger[:-1]} is not approved: {rel}")
            if re.search(r"\$\{\{\s*github\.event\.pull_request\.", text):
                fail(f"untrusted pull-request metadata interpolation detected in workflow: {rel}")
            for uses in re.findall(r"^\s*-?\s*uses:\s*([^\s#]+)", text, re.M):
                if uses.startswith(("./", "docker://")):
                    continue
                if "@" not in uses or not re.fullmatch(r"[0-9a-f]{40}", uses.rsplit("@", 1)[1]):
                    fail(f"workflow action must be pinned to full commit SHA: {rel}: {uses}")
            if "actions/checkout@" in text and "persist-credentials: false" not in text:
                fail(f"checkout credentials must not be persisted in workflow: {rel}")
            if re.search(r"(?:curl|wget)[^\n|]*\|\s*(?:ba)?sh\b", text):
                fail(f"download-to-shell pattern detected: {rel}")

    validate_workflow = read_text(".github/workflows/validate.yml")
    regression_workflow = read_text(".github/workflows/regression.yml")
    release_workflow = read_text(".github/workflows/release.yml")

    for label, workflow in (
        ("validation", validate_workflow),
        ("regression", regression_workflow),
    ):
        for marker in (
            "workflow_dispatch:",
            "concurrency:",
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "lua5.1 tests/run.lua",
        ):
            if marker not in workflow:
                fail(f"{label} workflow missing hardened test/concurrency gate: {marker}")

    for marker in (
        "scripts/build_sbom.py",
        "SBOM.spdx.json",
    ):
        if marker not in validate_workflow:
            fail(f"validation workflow missing deterministic SBOM gate: {marker}")
    for marker in (
        "scripts/build_sbom.py",
        "sbom-path: dist/SBOM.spdx.json",
        '"dist/SBOM.spdx.json"',
        "gh attestation verify",
        "--predicate-type https://spdx.dev/Document/v2.3",
    ):
        if marker not in release_workflow:
            fail(f"release workflow missing least-privilege SBOM/attestation verification gate: {marker}")

    if not re.search(r"(?ms)^permissions:\n  contents: read\s*$", release_workflow):
        fail("release workflow top-level permissions must default to contents: read")

    validate_release_match = re.search(r"(?ms)^  validate-release:\n(.*?)(?=^  attest-release:\n)", release_workflow)
    if not validate_release_match:
        fail("release workflow must separate read-only validation/build from attestation")
    validate_release_block = validate_release_match.group(1)
    for forbidden in ("id-token: write", "attestations: write", "artifact-metadata: write", "contents: write"):
        if forbidden in validate_release_block:
            fail(f"release validation/build job must remain read-only: {forbidden}")
    for marker in ("lua5.1 tests/run.lua", "scripts/audit_repository.py", "Build deterministic release archive and SPDX SBOM", "Upload exact validated release payload"):
        if marker not in validate_release_block:
            fail(f"release validation/build contract drifted: {marker}")

    attest_match = re.search(r"(?ms)^  attest-release:\n(.*?)(?=^  draft-release:\n)", release_workflow)
    if not attest_match:
        fail("release workflow missing isolated attestation job")
    attest_block = attest_match.group(1)
    for marker in (
        "needs: validate-release",
        "id-token: write",
        "attestations: write",
        "artifact-metadata: write",
        "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6",
    ):
        if marker not in attest_block:
            fail(f"release attestation contract drifted: {marker}")

    draft_match = re.search(r"(?ms)^  draft-release:\n(.*)$", release_workflow)
    if not draft_match:
        fail("release workflow missing draft publication job")
    draft_block = draft_match.group(1)
    for marker in (
        "needs: [validate-release, attest-release]",
        "contents: write",
        "attestations: read",
        "gh attestation verify",
        "--predicate-type https://spdx.dev/Document/v2.3",
        "gh release create",
        "--draft",
    ):
        if marker not in draft_block:
            fail(f"draft release publication contract drifted: {marker}")

    print(
        f"ok - repository audit passed ({len(files)} tracked files; {len(entries)} runtime files; "
        "critical audit files/workflow triggers/action pins/checkout credentials/Blizzard policy/SBOM/test concurrency/least-privilege release locked)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
