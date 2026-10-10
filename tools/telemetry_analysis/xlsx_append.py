"""Append Artifact Tool sheets while preserving every original worksheet byte."""
from __future__ import annotations

import copy
import posixpath
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT = "http://schemas.openxmlformats.org/package/2006/content-types"
OWNED = {"观测汇总", "技能观测", "退出观察", "数据来源", "自动参考"}
ET.register_namespace("", NS)
ET.register_namespace("r", REL)


def tag(name: str) -> str:
    return f"{{{NS}}}{name}"


def xml_bytes(root: ET.Element) -> bytes:
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def resolve_part(target: str) -> str:
    return target.lstrip("/") if target.startswith("/") else posixpath.normpath("xl/" + target)


def cell_value(cell: ET.Element, strings: list[str]) -> str | float | bool | None:
    formula = cell.find(tag("f"))
    if formula is not None:
        return "=" + (formula.text or "")
    if cell.get("t") == "inlineStr":
        return "".join(cell.find(tag("is")).itertext())
    value = cell.find(tag("v"))
    if value is None or value.text is None:
        return None
    kind = cell.get("t")
    if kind == "s":
        return strings[int(value.text)]
    if kind in {"str", "e", "d"}:
        return value.text
    if kind == "b":
        return value.text == "1"
    return float(value.text)


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    return ["".join(node.itertext()) for node in ET.fromstring(archive.read("xl/sharedStrings.xml"))]


def read_auto(source: Path) -> list[list[str | float | None]]:
    with zipfile.ZipFile(source) as archive:
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        selected = [s for s in workbook.findall(tag("sheets") + "/" + tag("sheet"))
                    if s.get("name") == "自动参考"]
        if not selected:
            return []
        mapping = {r.attrib["Id"]: resolve_part(r.attrib["Target"])
                   for r in ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))}
        strings = shared_strings(archive)
        root = ET.fromstring(archive.read(mapping[selected[0].attrib[f"{{{REL}}}id"]]))
        rows: list[list[str | float | None]] = []
        for row in root.findall(tag("sheetData") + "/" + tag("row")):
            if int(row.attrib["r"]) < 6:
                continue
            result: list[str | float | None] = [None] * 8
            for cell in row:
                index = ord(cell.attrib["r"][0]) - ord("A")
                if index >= 8:
                    continue
                if cell.find(tag("f")) is not None:
                    raise ValueError("manual formulas in managed automatic reference; preserve source and review")
                result[index] = cell_value(cell,strings)
            if result[0] is not None:
                rows.append(result)
        return rows


def read_managed_cells(source: Path) -> dict[str, dict[str, str | float | bool | None]]:
    result: dict[str, dict[str, str | float | bool | None]] = {}
    with zipfile.ZipFile(source) as archive:
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        mapping = {r.attrib["Id"]: resolve_part(r.attrib["Target"])
                   for r in ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))}
        strings = shared_strings(archive)
        for sheet in workbook.findall(tag("sheets") + "/" + tag("sheet")):
            name = sheet.attrib["name"]
            if name not in OWNED:
                continue
            result[name] = {}
            root = ET.fromstring(archive.read(mapping[sheet.attrib[f"{{{REL}}}id"]]))
            for cell in root.findall(".//" + tag("c")):
                result[name][cell.attrib["r"]] = cell_value(cell,strings)
    return result


def merge_styles(original: ET.Element, added: ET.Element) -> int:
    offsets: dict[str, int] = {}
    for name in ("fonts", "fills", "borders", "cellStyleXfs", "cellXfs"):
        parent = original.find(tag(name))
        if parent is None:
            parent = ET.SubElement(original, tag(name))
        offsets[name] = len(parent)
    base_formats = original.find(tag("numFmts"))
    if base_formats is None:
        base_formats = ET.Element(tag("numFmts"))
        original.insert(0, base_formats)
    format_map: dict[int, int] = {}
    maximum = max([163] + [int(node.attrib["numFmtId"]) for node in base_formats])
    for node in added.findall(tag("numFmts") + "/" + tag("numFmt")):
        maximum += 1
        format_map[int(node.attrib["numFmtId"])] = maximum
        new = copy.deepcopy(node)
        new.set("numFmtId", str(maximum))
        base_formats.append(new)
    base_formats.set("count", str(len(base_formats)))
    for name in ("fonts", "fills", "borders", "cellStyleXfs", "cellXfs"):
        parent = original.find(tag(name))
        assert parent is not None
        source = added.find(tag(name))
        for node in source if source is not None else []:
            new = copy.deepcopy(node)
            if name in ("cellStyleXfs", "cellXfs"):
                for attribute, collection in (("fontId", "fonts"), ("fillId", "fills"),
                                               ("borderId", "borders"), ("xfId", "cellStyleXfs")):
                    if attribute in new.attrib:
                        new.set(attribute, str(int(new.attrib[attribute]) + offsets[collection]))
                identifier = int(new.get("numFmtId", "0"))
                if identifier in format_map:
                    new.set("numFmtId", str(format_map[identifier]))
            parent.append(new)
        parent.set("count", str(len(parent)))
    return offsets["cellXfs"]


def append_observations(source: Path, observations: Path, destination: Path) -> None:
    if source.resolve() == destination.resolve() or destination.exists():
        raise ValueError("never overwrite source or existing output workbook")
    with zipfile.ZipFile(source) as archive:
        original = {name: archive.read(name) for name in archive.namelist()}
    with zipfile.ZipFile(observations) as archive:
        added = {name: archive.read(name) for name in archive.namelist()}
    workbook = ET.fromstring(original["xl/workbook.xml"])
    sheets = workbook.find(tag("sheets"))
    assert sheets is not None
    # Require the semantic v0.4 target sheet, not a guess based on filename alone.
    names = {sheet.attrib["name"] for sheet in sheets}
    if "目标节奏" not in names or "技能估值" not in names:
        raise ValueError("workbook is not the specified v0.4 model (missing semantic sheets)")
    relationships = ET.fromstring(original["xl/_rels/workbook.xml.rels"])
    content = ET.fromstring(original["[Content_Types].xml"])
    added_book = ET.fromstring(added["xl/workbook.xml"])
    added_rels = ET.fromstring(added["xl/_rels/workbook.xml.rels"])
    added_map = {node.attrib["Id"]: resolve_part(node.attrib["Target"]) for node in added_rels}
    existing_map = {node.attrib["Id"]: node for node in relationships}
    # Refresh only our five data sheets; original model sheets remain byte-identical.
    for sheet in list(sheets):
        if sheet.attrib["name"] in OWNED:
            relationships.remove(existing_map[sheet.attrib[f"{{{REL}}}id"]])
            sheets.remove(sheet)
    styles = ET.fromstring(original["xl/styles.xml"])
    style_offset = merge_styles(styles, ET.fromstring(added["xl/styles.xml"]))
    original["xl/styles.xml"] = xml_bytes(styles)
    strings = ET.fromstring(original.get("xl/sharedStrings.xml", xml_bytes(ET.Element(tag("sst")))))
    string_offset = len(strings)
    if "xl/sharedStrings.xml" in added:
        for string in ET.fromstring(added["xl/sharedStrings.xml"]):
            strings.append(copy.deepcopy(string))
    strings.set("count", str(len(strings)))
    strings.set("uniqueCount", str(len(strings)))
    original["xl/sharedStrings.xml"] = xml_bytes(strings)
    if not any(node.get("Type", "").endswith("/sharedStrings") for node in relationships):
        ET.SubElement(relationships, f"{{{PKG}}}Relationship", {
            "Id": "telemetry17_strings", "Type": REL + "/sharedStrings", "Target": "sharedStrings.xml"})
        ET.SubElement(content, f"{{{CONTENT}}}Override", {"PartName": "/xl/sharedStrings.xml",
            "ContentType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"})
    next_id = max(int(sheet.attrib["sheetId"]) for sheet in sheets) + 1
    for index, sheet in enumerate(added_book.findall(tag("sheets") + "/" + tag("sheet")), 1):
        if sheet.attrib["name"] not in OWNED:
            raise ValueError("unexpected observation sheet")
        part = added_map[sheet.attrib[f"{{{REL}}}id"]]
        root = ET.fromstring(added[part])
        for cell in root.findall(".//" + tag("c")):
            if "s" in cell.attrib:
                cell.set("s", str(int(cell.attrib["s"]) + style_offset))
            if cell.get("t") == "s":
                value = cell.find(tag("v"))
                assert value is not None and value.text is not None
                value.text = str(int(value.text) + string_offset)
        for node in root.findall(".//" + tag("col")) + root.findall(".//" + tag("row")):
            for attribute in ("style", "s"):
                if attribute in node.attrib:
                    node.set(attribute, str(int(node.attrib[attribute]) + style_offset))
        new_part = f"xl/worksheets/telemetry17_sheet{index}.xml"
        original[new_part] = xml_bytes(root)
        relation_id = f"telemetry17_sheet{index}"
        ET.SubElement(relationships, f"{{{PKG}}}Relationship", {"Id": relation_id,
            "Type": REL + "/worksheet", "Target": f"worksheets/telemetry17_sheet{index}.xml"})
        new_sheet = copy.deepcopy(sheet)
        new_sheet.set("sheetId", str(next_id + index - 1))
        new_sheet.set(f"{{{REL}}}id", relation_id)
        sheets.append(new_sheet)
        if not any(node.get("PartName") == "/" + new_part for node in content):
            ET.SubElement(content, f"{{{CONTENT}}}Override", {"PartName": "/" + new_part,
                "ContentType": "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"})
    original["xl/workbook.xml"] = xml_bytes(workbook)
    original["xl/_rels/workbook.xml.rels"] = xml_bytes(relationships)
    original["[Content_Types].xml"] = xml_bytes(content)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in original.items():
            archive.writestr(name, data)
    # Read back and prove original model cells, formulas and native objects were not rewritten.
    changed_parts = {"xl/workbook.xml", "xl/_rels/workbook.xml.rels", "[Content_Types].xml",
                     "xl/styles.xml", "xl/sharedStrings.xml"}
    with zipfile.ZipFile(source) as before, zipfile.ZipFile(destination) as after:
        for name in before.namelist():
            if name not in changed_parts and not name.startswith("xl/worksheets/telemetry17_"):
                if before.read(name) != after.read(name):
                    raise ValueError(f"original workbook part changed: {name}")
        for name in after.namelist():
            if name.endswith(".xml"):
                root = ET.fromstring(after.read(name))
                for cell in root.findall(".//" + tag("c")):
                    if cell.get("t") == "e":
                        raise ValueError(f"formula error in saved workbook: {name}:{cell.get('r')}")
