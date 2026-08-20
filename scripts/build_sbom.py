#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import build_release

ROOT = Path(__file__).resolve().parents[1]
ADDON = "MDTPullMarker"
REPOSITORY = "Yolol100/MDTPullMarker"


def fail(message: str) -> None:
    raise SystemExit(message)


def toc_version() -> str:
    for raw in (ROOT / "MDTPullMarker.toc").read_text(encoding="utf-8").splitlines():
        if raw.startswith("## Version:"):
            value = raw.split(":", 1)[1].strip()
            if value:
                return value
    fail("TOC version is missing")


def git_value(*args: str) -> str:
    try:
        return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"git metadata is required for deterministic SBOM generation: {exc}")


def created_at() -> str:
    epoch = os.environ.get("SOURCE_DATE_EPOCH", "").strip()
    if epoch:
        try:
            stamp = datetime.fromtimestamp(int(epoch), tz=timezone.utc)
        except (ValueError, OverflowError) as exc:
            fail(f"invalid SOURCE_DATE_EPOCH: {exc}")
        return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")
    raw = git_value("show", "-s", "--format=%ct", "HEAD")
    try:
        stamp = datetime.fromtimestamp(int(raw), tz=timezone.utc)
    except (ValueError, OverflowError) as exc:
        fail(f"invalid git commit timestamp: {exc}")
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def checksum(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build(archive: Path, output: Path) -> None:
    if not archive.is_file():
        fail(f"release archive does not exist: {archive}")
    files = build_release.package_files()
    version = toc_version()
    commit = git_value("rev-parse", "HEAD")

    file_rows = []
    verification_inputs: list[str] = []
    relationships = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": "SPDXRef-Package",
        }
    ]
    for index, rel in enumerate(files, start=1):
        source = ROOT / rel
        sha1 = checksum(source, "sha1")
        sha256 = checksum(source, "sha256")
        verification_inputs.append(sha1)
        spdx_id = f"SPDXRef-File-{index}"
        file_rows.append(
            {
                "fileName": f"./{ADDON}/{rel}",
                "SPDXID": spdx_id,
                "checksums": [
                    {"algorithm": "SHA1", "checksumValue": sha1},
                    {"algorithm": "SHA256", "checksumValue": sha256},
                ],
                "licenseConcluded": "NOASSERTION",
                "copyrightText": "NOASSERTION",
            }
        )
        relationships.append(
            {
                "spdxElementId": "SPDXRef-Package",
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": spdx_id,
            }
        )

    package_verification = hashlib.sha1(
        "".join(sorted(verification_inputs)).encode("ascii")
    ).hexdigest()
    archive_sha256 = checksum(archive, "sha256")
    document = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"{ADDON}-{version}",
        "documentNamespace": f"https://github.com/{REPOSITORY}/sbom/{commit}",
        "creationInfo": {
            "created": created_at(),
            "creators": ["Tool: scripts/build_sbom.py"],
        },
        "packages": [
            {
                "name": ADDON,
                "SPDXID": "SPDXRef-Package",
                "versionInfo": version,
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": True,
                "packageVerificationCode": {
                    "packageVerificationCodeValue": package_verification
                },
                "checksums": [
                    {"algorithm": "SHA256", "checksumValue": archive_sha256}
                ],
                "licenseConcluded": "MIT",
                "licenseDeclared": "MIT",
                "copyrightText": "Copyright (c) 2026 Webactueel Team",
            }
        ],
        "files": file_rows,
        "relationships": relationships,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(document, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    archive = Path(args.archive)
    output = Path(args.output)
    if not archive.is_absolute():
        archive = ROOT / archive
    if not output.is_absolute():
        output = ROOT / output
    build(archive, output)
    print(f"ok - wrote deterministic SPDX 2.3 SBOM: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
