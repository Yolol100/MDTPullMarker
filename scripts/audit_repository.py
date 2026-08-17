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
FORBIDDEN_PATH_PARTS = {".idea", ".vscode", "__pycache__", ".pytest_cache", "node_modules", "dist", "build", "coverage", ".env"}
FORBIDDEN_SUFFIXES = {".log", ".tmp", ".swp", ".swo", ".bak", ".orig", ".rej", ".pem", ".p12", ".pfx"}
SECRET_PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "GitHub token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    "Slack token": re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{20,}\b"),
    "OpenAI key": re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}\b"),
}


def fail(message: str) -> None:
    print(f"error - {message}", file=sys.stderr)
    raise SystemExit(1)


def git_files() -> list[str]:
    raw = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    return [x.decode("utf-8") for x in raw.split(b"\0") if x]


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
    entries = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            entries.append(line.replace("\\", "/"))
    return entries


def main() -> int:
    files = git_files()
    if not files:
        fail("repository contains no tracked files")
    seen: dict[str, str] = {}
    for rel in files:
        if unicodedata.normalize("NFC", rel) != rel:
            fail(f"path is not NFC-normalized: {rel}")
        p = PurePosixPath(rel)
        if p.is_absolute() or ".." in p.parts or any(part in FORBIDDEN_PATH_PARTS for part in p.parts):
            fail(f"forbidden tracked path: {rel}")
        if p.suffix.lower() in FORBIDDEN_SUFFIXES or rel.endswith("~"):
            fail(f"temporary/sensitive file must not be tracked: {rel}")
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

    for rel in files:
        if rel.startswith(".github/workflows/") and rel.endswith((".yml", ".yaml")):
            text = read_text(rel)
            if "permissions:" not in text:
                fail(f"workflow must declare permissions explicitly: {rel}")
            for uses in re.findall(r"^\s*-?\s*uses:\s*([^\s#]+)", text, re.M):
                if uses.startswith(("./", "docker://")):
                    continue
                if "@" not in uses or not re.fullmatch(r"[0-9a-f]{40}", uses.rsplit("@", 1)[1]):
                    fail(f"workflow action must be pinned to full commit SHA: {rel}: {uses}")
            if re.search(r"(?:curl|wget)[^\n|]*\|\s*(?:ba)?sh\b", text):
                fail(f"download-to-shell pattern detected: {rel}")

    print(f"ok - repository audit passed ({len(files)} tracked files; {len(entries)} runtime files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
