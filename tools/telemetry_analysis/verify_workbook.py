"""Read-only checks: preserved model parts and truthful per-cell change report."""
from __future__ import annotations

import argparse
import csv
import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from xlsx_append import OWNED, read_managed_cells, tag


def same_report_value(raw: str, value: str | float | bool | None) -> bool:
    if value is None:
        return raw == ""
    if isinstance(value, bool):
        return raw == str(value).lower()
    if isinstance(value, (int, float)):
        try:
            return float(raw) == value
        except ValueError:
            return False
    # CSV textual formula-like values are escaped by the writer.
    escaped = "'" + value if value.startswith(("=", "+", "-", "@")) else value
    return raw == escaped


def verify(source: Path, output: Path, report: Path) -> dict[str, int]:
    mutable = {"xl/workbook.xml", "xl/_rels/workbook.xml.rels", "[Content_Types].xml",
               "xl/styles.xml", "xl/sharedStrings.xml"}
    preserved = 0
    formulas = 0
    with zipfile.ZipFile(source) as before, zipfile.ZipFile(output) as after:
        for name in before.namelist():
            if name not in mutable and not name.startswith("xl/worksheets/telemetry17_"):
                if before.read(name) != after.read(name):
                    raise ValueError(f"original part changed: {name}")
                preserved += 1
                if name.startswith("xl/worksheets/") and name.endswith(".xml"):
                    formulas += len(ET.fromstring(before.read(name)).findall(".//" + tag("f")))
        workbook = ET.fromstring(after.read("xl/workbook.xml"))
        names = [s.attrib["name"] for s in workbook.findall(tag("sheets") + "/" + tag("sheet"))]
        if len(names) != len(set(names)) or not OWNED.issubset(names):
            raise ValueError("duplicate or missing observation sheets")
        for name in after.namelist():
            if name.endswith(".xml"):
                for cell in ET.fromstring(after.read(name)).findall(".//" + tag("c")):
                    if cell.get("t") == "e":
                        raise ValueError(f"saved error cell: {name}:{cell.get('r')}")
    old_cells = read_managed_cells(source)
    new_cells = read_managed_cells(output)
    checked: set[tuple[str, str]] = set()
    with report.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            sheet, cell = row["sheet"], row["cell"]
            key = (sheet, cell)
            if key in checked:
                raise ValueError(f"duplicate cell report: {key}")
            checked.add(key)
            old = old_cells.get(sheet, {}).get(cell)
            new = new_cells.get(sheet, {}).get(cell)
            if not same_report_value(row["old_value"], old) or not same_report_value(row["new_value"], new):
                raise ValueError(f"change report differs from saved workbook: {key}")
    expected = {(sheet, cell) for sheet, cells in new_cells.items() for cell, value in cells.items()
                if value is not None}
    expected |= {(sheet, cell) for sheet, cells in old_cells.items() for cell, value in cells.items()
                 if value is not None and new_cells.get(sheet, {}).get(cell) != value}
    if expected - checked:
        raise ValueError("change report omits populated or cleared cells")
    return {"sheets": len(names), "preserved_parts": preserved,
            "preserved_formulas": formulas, "validated_changes": len(checked)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("changes", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.source, args.output, args.changes), ensure_ascii=False))
