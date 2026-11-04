"""Read-only source checks for the World of Warcraft add-on package."""

from __future__ import annotations

import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MDTPullMarker.toc"


def addon_entries() -> list[str]:
    lines = TOC.read_text(encoding="utf-8-sig").splitlines()
    return [
        line.strip().replace("\\", "/")
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    ]


class AddonSourceContractTest(unittest.TestCase):
    def test_manifest_has_no_missing_or_duplicate_files(self) -> None:
        entries = addon_entries()
        self.assertTrue(entries, "TOC must load add-on source")
        self.assertEqual(len(entries), len({entry.casefold() for entry in entries}))
        for entry in entries:
            with self.subTest(entry=entry):
                self.assertFalse(Path(entry).is_absolute())
                self.assertNotIn("..", Path(entry).parts)
                self.assertTrue((ROOT / entry).is_file(), f"Missing TOC file: {entry}")

    def test_all_addon_lua_sources_are_referenced(self) -> None:
        loaded = {entry for entry in addon_entries() if entry.endswith(".lua")}
        found = {
            path.relative_to(ROOT).as_posix()
            for path in ROOT.rglob("*.lua")
            if not any(part.startswith(".") or part == "tests" for part in path.relative_to(ROOT).parts)
        }
        self.assertEqual(found, loaded, "All non-test Lua files must be loaded exactly once")

    def test_bindings_xml_is_well_formed(self) -> None:
        root = ET.parse(ROOT / "Bindings.xml").getroot()
        self.assertEqual(root.tag, "Bindings")
        self.assertTrue(root.findall("Binding"), "At least one binding is required")


if __name__ == "__main__":
    unittest.main()
