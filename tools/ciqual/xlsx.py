"""Lecture minimale d'un .xlsx (première feuille) avec la bibliothèque standard."""
import re
import zipfile
import xml.etree.ElementTree as ET

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def _col(ref):
    letters = re.match(r"[A-Z]+", ref).group(0)
    n = 0
    for c in letters:
        n = n * 26 + ord(c) - 64
    return n - 1


def rows(path):
    with zipfile.ZipFile(path) as z:
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS):
                shared.append("".join(t.text or "" for t in si.iter(f"{{{NS['m']}}}t")))
        sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
        for row in sheet.find("m:sheetData", NS).findall("m:row", NS):
            values = {}
            for c in row.findall("m:c", NS):
                v = c.find("m:v", NS)
                if v is None:
                    inline = c.find("m:is", NS)
                    text = "".join(t.text or "" for t in inline.iter(f"{{{NS['m']}}}t")) if inline is not None else ""
                else:
                    text = shared[int(v.text)] if c.get("t") == "s" else v.text
                values[_col(c.get("r"))] = text
            if values:
                yield [values.get(i, "") for i in range(max(values) + 1)]
