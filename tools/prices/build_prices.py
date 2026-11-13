"""Construit prices.json (prix médians France, Open Prices) pour Shreddish, spec 011.

Usage : python build_prices.py prices.parquet ciqual.json foods.json sortie.json
Dépendance : duckdb (pip install duckdb). Source : Open Prices (Open Food Facts), licence ODbL.

Prix au kg acheté (au litre pour les liquides) et part comestible ; aliment cuit : prix ramené au poids cuit.
Prix par aliment : quartile bas des 12 derniers mois (prix promo exclus) dès 8 relevés ; en dessous,
fenêtre de 24 mois et moyenne des médianes par enseigne.
"""
import datetime
import json
import re
import statistics
import sys
import unicodedata

import duckdb

MIN_COUNT = 8
# Aliment Ciqual cuit : prix au g cuit = prix au g cru × "cooked" (g crus par g cuit) ; sans "cooked", non tarifé.
COOKED = re.compile(r"\b(cuit|cuite|cuits|cuites|bouilli|bouillie|roti|rotie|grille|grillee|poele|poelee|frit|frite|vapeur|poche|coque)\b|^oeuf dur")


def norm(text):
    text = (text or "").lower().replace("œ", "oe").replace("æ", "ae").replace("’", "'")
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


def load_rows(parquet):
    con = duckdb.connect()
    query = f"""
        select date, location_osm_brand brand,
               coalesce(product_product_name, product_name, '') pname,
               coalesce(product_categories_tags, [category_tag]) cats,
               case when type = 'PRODUCT' and product_product_quantity > 0
                         and product_product_quantity_unit in ('g', 'ml')
                    then price / product_product_quantity * 1000
                    when type = 'CATEGORY' and price_per = 'KILOGRAM' then price end per_kg,
               case when type = 'CATEGORY' and price_per = 'UNIT' then price end per_unit
        from '{parquet}'
        where currency = 'EUR' and location_osm_address_country_code = 'FR' and duplicate_of is null
          and not coalesce(price_is_discounted, false) and price > 0
          and date >= current_date - interval 730 day
    """
    rows = []
    for date, brand, pname, cats, per_kg, per_unit in con.sql(query).fetchall():
        rows.append({
            "date": date, "brand": norm(brand or "autre").split()[0] if brand else "autre",
            "name": norm(pname), "cats": set(cats or []),
            "per_kg": float(per_kg) if per_kg else None, "per_unit": float(per_unit) if per_unit else None,
        })
    return rows


def matches(entry, row):
    if not row["cats"] & set(entry["tags"]):
        return False
    name = row["name"]
    if entry.get("name") and not any(norm(k) in name for k in entry["name"]):
        return False
    return not any(norm(k) in name for k in entry.get("not", []))


def trimmed(values):
    if len(values) < 3:
        return values
    median = statistics.median(values)
    return [v for v in values if median / 4 <= v <= median * 4]


def estimate(rows, key):
    """(prix, méthode, nombre) : quartile bas sur 12 mois, sinon moyenne des médianes par enseigne sur 24 mois."""
    cutoff = datetime.date.today() - datetime.timedelta(days=365)
    recent = trimmed([r[key] for r in rows if r[key] and r["date"] >= cutoff])
    if len(recent) >= MIN_COUNT:
        return statistics.quantiles(recent, n=4)[0], "q1", len(recent)
    by_brand = {}
    for r in rows:
        if r[key]:
            by_brand.setdefault(r["brand"], []).append(r[key])
    if not by_brand:
        return None, "aucun", 0
    medians = trimmed([statistics.median(v) for v in by_brand.values()])
    count = sum(len(v) for v in by_brand.values())
    return statistics.mean(medians), f"enseignes:{len(by_brand)}", count


def main(parquet, ciqual_path, foods_path, out_path):
    rows = load_rows(parquet)
    entries = json.load(open(foods_path, encoding="utf-8"))
    ciqual = json.load(open(ciqual_path, encoding="utf-8"))["foods"]
    priced = {}
    report = []
    for entry in entries:
        selected = [r for r in rows if matches(entry, r)]
        per_kg, method, count = estimate(selected, "per_kg")
        per_unit, _, unit_count = estimate(selected, "per_unit")
        piece = entry.get("piece")
        if per_kg is None and per_unit and piece:
            per_kg, method = per_unit / piece * 1000, "pièce"
        if piece and per_unit is None and per_kg:
            per_unit = per_kg * piece / 1000
        priced[entry["id"]] = (per_kg, entry.get("yield", 1.0))
        report.append((entry["id"], per_kg, method, count, per_unit, unit_count))

    foods = {}
    unmatched = []
    for code, name, group, *_ in ciqual:
        key = norm(name)
        for entry in entries:
            if any(re.search(p, key) for p in entry["ciqual"]):
                per_kg, yield_ = priced[entry["id"]]
                if COOKED.search(key):
                    if "cooked" not in entry:
                        break
                    yield_ = round(yield_ / entry["cooked"], 3)
                if per_kg:
                    foods[str(code)] = [round(per_kg, 2), yield_]
                break
    for entry in entries:
        if not any(any(re.search(p, norm(f[1])) for p in entry["ciqual"]) for f in ciqual):
            unmatched.append(entry["id"])

    groups = {}
    by_group = {}
    for code, name, group, *_ in ciqual:
        if str(code) in foods:
            by_group.setdefault(group, []).append(foods[str(code)][0])
    for group, values in by_group.items():
        values.sort()
        groups[group] = [round(values[int(len(values) * 0.1)], 2), round(values[int(len(values) * 0.9)], 2)]

    out = {
        "source": "Open Prices (Open Food Facts), ODbL — prix France (quartile bas) relevés au " + datetime.date.today().isoformat(),
        "columns": ["eur_per_kg", "edible_yield"],
        "foods": foods, "groups": groups,
    }
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(out, handle, ensure_ascii=False, separators=(",", ":"))
    for item in report:
        print("%-24s %8s €/kg  %-12s n=%-4d pièce=%s (n=%d)" % (
            item[0], f"{item[1]:.2f}" if item[1] else "-", item[2], item[3],
            f"{item[4]:.2f}" if item[4] else "-", item[5]))
    print("Ciqual couverts :", len(foods), "· entrées sans aliment Ciqual :", unmatched, file=sys.stderr)


if __name__ == "__main__":
    main(*sys.argv[1:5])
