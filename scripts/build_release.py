#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import sys
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MDTPullMarker.toc"
ADDON = "MDTPullMarker"
FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def fail(message: str) -> None:
    print(f"error - {message}", file=sys.stderr)
    raise SystemExit(1)


def toc_entries() -> list[str]:
    entries: list[str] = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            entries.append(line.replace("\\", "/"))
    return entries


def package_files() -> list[str]:
    files = [TOC.name]
    for optional in ("Bindings.xml", "LICENSE"):
        if (ROOT / optional).is_file():
            files.append(optional)
    files.extend(toc_entries())
    if len(files) != len(set(files)):
        fail("release inventory contains duplicate paths")
    for rel in files:
        path = ROOT / rel
        if not path.is_file():
            fail(f"release inventory file is missing: {rel}")
        p = PurePosixPath(rel)
        if p.is_absolute() or ".." in p.parts:
            fail(f"unsafe release path: {rel}")
    return files


def build(output: Path) -> str:
    output.parent.mkdir(parents=True, exist_ok=True)
    files = package_files()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for rel in files:
            data = (ROOT / rel).read_bytes()
            arcname = f"{ADDON}/{rel}"
            info = zipfile.ZipInfo(arcname, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (0o100644 << 16)
            zf.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)

    with zipfile.ZipFile(output) as zf:
        names = [name for name in zf.namelist() if not name.endswith("/")]
        if not names:
            fail("release ZIP is empty")
        if len(names) != len(set(names)):
            fail("release ZIP contains duplicate entries")
        if any(PurePosixPath(name).parts[0] != ADDON for name in names):
            fail("release ZIP contains a root outside the addon folder")
        expected_toc = f"{ADDON}/{ADDON}.toc"
        if expected_toc not in names:
            fail(f"release ZIP is missing {expected_toc}")
        expected = {f"{ADDON}/{rel}" for rel in files}
        if set(names) != expected:
            fail("release ZIP inventory differs from the tested runtime allowlist")
        for name in names:
            rel = PurePosixPath(name).relative_to(ADDON).as_posix()
            if zf.read(name) != (ROOT / rel).read_bytes():
                fail(f"packaged byte mismatch: {rel}")

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    return digest


def main() -> int:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "dist" / "MDTPullMarker.zip"
    digest = build(output)
    print(f"{digest}  {output.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
