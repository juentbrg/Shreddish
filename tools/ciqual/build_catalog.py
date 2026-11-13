"""Catalogue compact Ciqual pour l'app (spec 010).

Usage : python3 -I tools/ciqual/build_catalog.py <Table Ciqual 2025_FR.xlsx> <sortie.json>
Source : Table de composition nutritionnelle des aliments Ciqual 2025, ANSES, Licence Ouverte Etalab 2.0,
doi:10.57745/RDMHWY. Garde par aliment : code, nom, groupe, kcal, protéines, glucides, lipides pour 100 g.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xlsx  # noqa: E402

COL_GROUP, COL_CODE, COL_NAME = 0, 6, 7
COL_KCAL, COL_PROTEIN, COL_CARBS, COL_FAT = 10, 14, 16, 17
EXCLUDED_GROUPS = {"00", "11"}  # sans groupe, aliments infantiles


def number(text):
    """« 12,5 » → 12.5 ; « traces » ou « < 0,5 » → 0 ; « - » ou vide → None."""
    text = (text or "").strip()
    if not text or text == "-":
        return None
    if text == "traces" or text.startswith("<"):
        return 0.0
    try:
        return float(text.replace(",", "."))
    except ValueError:
        return None


def build(source):
    rows = xlsx.rows(source)
    next(rows)
    foods = []
    for row in rows:
        row = row + [""] * (COL_FAT + 1 - len(row))
        if row[COL_GROUP] in EXCLUDED_GROUPS:
            continue
        protein, carbs, fat = (number(row[i]) for i in (COL_PROTEIN, COL_CARBS, COL_FAT))
        if None in (protein, carbs, fat):
            continue
        kcal = number(row[COL_KCAL])
        if kcal is None:
            kcal = 4 * protein + 4 * carbs + 9 * fat
        name = " ".join(row[COL_NAME].split())
        foods.append([int(row[COL_CODE]), name, int(row[COL_GROUP]),
                      round(kcal), round(protein, 1), round(carbs, 1), round(fat, 1)])
    foods.sort(key=lambda food: food[0])
    return {
        "source": "Ciqual 2025, ANSES, Licence Ouverte Etalab 2.0",
        "columns": ["code", "name", "group", "kcal", "protein_g", "carbs_g", "fat_g"],
        "foods": foods,
    }


if __name__ == "__main__":
    catalog = build(sys.argv[1])
    with open(sys.argv[2], "w", encoding="utf-8") as out:
        json.dump(catalog, out, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(catalog['foods'])} aliments → {sys.argv[2]}")
