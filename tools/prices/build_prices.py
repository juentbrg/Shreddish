"""Construit prices.json (prix France médians, Open Prices) pour Shreddish, specs 011, 018 et 020.

Usage : python build_prices.py prices.parquet ciqual.json foods.json sortie.json
Entrée de foods.json avec "price" : prix de repli (€/kg) si moins de 8 relevés.
Dépendance : duckdb (pip install duckdb). Source : Open Prices (Open Food Facts), licence ODbL.

Prix au kg acheté (au litre pour les liquides) et part comestible ; aliment cuit : prix ramené au poids cuit.
Chaque aliment Ciqual est rattaché à son produit acheté (libellé, unité d'achat, rayon) pour la liste de courses.
Prix par aliment : médiane des 12 derniers mois (prix promo exclus) dès 8 relevés ; en dessous, fenêtre de
24 mois et moyenne des médianes par enseigne (spec 020 : le 3e quartile dépassait les prix des drives).
Formats vendus : ceux de foods.json (formats réels en rayon, plusieurs par produit), chacun calé sur la taille
la plus relevée à moins de 8 % (boîte de thon 140 g, pas 130 g) ; jamais de format absent de foods.json (spec 020).
"""
import datetime
import json
import re
import statistics
import sys
import unicodedata

import duckdb

MIN_COUNT = 8
QUANTILE = 0.5
# Taille relevée retenue pour caler un format : au moins 3 relevés.
PACK_MIN_COUNT = 3
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
               case when type = 'CATEGORY' and price_per = 'UNIT' then price end per_unit,
               case when type = 'PRODUCT' and product_product_quantity_unit in ('g', 'ml')
                    then product_product_quantity end qty
        from '{parquet}'
        where currency = 'EUR' and location_osm_address_country_code = 'FR' and duplicate_of is null
          and not coalesce(price_is_discounted, false) and price > 0
          and date >= current_date - interval 730 day
    """
    rows = []
    for date, brand, pname, cats, per_kg, per_unit, qty in con.sql(query).fetchall():
        rows.append({
            "date": date, "brand": norm(brand or "autre").split()[0] if brand else "autre",
            "name": norm(pname), "cats": set(cats or []),
            "per_kg": float(per_kg) if per_kg else None, "per_unit": float(per_unit) if per_unit else None,
            "qty": float(qty) if qty else None,
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


def quantile(values, q=QUANTILE):
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    position = (len(values) - 1) * q
    low = int(position)
    high = min(low + 1, len(values) - 1)
    return values[low] + (values[high] - values[low]) * (position - low)


def estimate(rows, key):
    """(prix, méthode, nombre) : médiane sur 12 mois, sinon moyenne des médianes par enseigne sur 24 mois."""
    cutoff = datetime.date.today() - datetime.timedelta(days=365)
    recent = trimmed([r[key] for r in rows if r[key] and r["date"] >= cutoff])
    if len(recent) >= MIN_COUNT:
        return quantile(recent), "mediane", len(recent)
    by_brand = {}
    for r in rows:
        if r[key]:
            by_brand.setdefault(r["brand"], []).append(r[key])
    if not by_brand:
        return None, "aucun", 0
    upper = trimmed([quantile(v) for v in by_brand.values()])
    count = sum(len(v) for v in by_brand.values())
    return statistics.mean(upper), f"enseignes:{len(by_brand)}", count


def near(size, packs, margin=0.1):
    return any(abs(size - pack) <= pack * margin for pack in packs)


def standard_rows(entry, rows):
    """Relevés comparables : vrac (prix au kg) et paquets aux formats courants de foods.json (± 10 %), sans
    sachets micro-ondes, produits frais traiteur ni mini-formats qui gonflent le prix au kg. Produit frais vendu
    au détail (sans formats) : vrac seul dès 8 relevés."""
    packs = entry.get("packs", [])
    loose = [r for r in rows if r["qty"] is None]
    if not packs:
        return loose if sum(1 for r in loose if r["per_kg"]) >= MIN_COUNT else rows
    return loose + [r for r in rows if r["qty"] is not None and near(r["qty"], packs)]


def observed_packs(entry, rows):
    """Formats de foods.json, chacun remplacé par la taille la plus relevée à moins de 8 % (relevés emballés de
    l'aliment) ; vide pour un produit à la pièce ou au détail. Les tailles relevées hors de ces formats viennent
    surtout de produits voisins (pâtes aux œufs en 250 g, huile vierge en 750 ml) : ignorées."""
    packs = entry.get("packs", [])
    # Légumes frais en filet (pommes de terre, oignons) : relevés surtout de produits voisins (grenaille, frits).
    if entry.get("piece") or not packs or entry["aisle"] == "fruits_legumes":
        return []
    counts = {}
    for r in rows:
        if r["qty"]:
            counts[round(r["qty"])] = counts.get(round(r["qty"]), 0) + 1
    snapped = []
    for pack in packs:
        near_sizes = [(c, s) for s, c in counts.items() if abs(s - pack) < pack * 0.08 and c >= PACK_MIN_COUNT]
        snapped.append(max(near_sizes)[1] if near_sizes else pack)
    return sorted(set(snapped))


def product_price(entry, per_kg):
    """Prix dans l'unité d'achat du produit : € par kg (ou L), ou € par pièce."""
    if not per_kg:
        return None
    return round(per_kg * entry["piece"] / 1000, 3) if entry.get("piece") else round(per_kg, 2)


def main(parquet, ciqual_path, foods_path, out_path):
    rows = load_rows(parquet)
    entries = json.load(open(foods_path, encoding="utf-8"))
    ciqual = json.load(open(ciqual_path, encoding="utf-8"))["foods"]
    priced = {}
    packs = {}
    report = []
    for entry in entries:
        selected = [r for r in rows if matches(entry, r)]
        per_kg, method, count = estimate(standard_rows(entry, selected), "per_kg")
        # Relevés trop rares ou anciens (filet mignon : surtout des plats préparés ; dinde : 2 enseignes) : prix de
        # repli de foods.json dès que la médiane récente manque.
        if entry.get("price") and method != "mediane":
            per_kg, method = entry["price"], "repli"
        per_unit, _, unit_count = estimate(selected, "per_unit")
        piece = entry.get("piece")
        if per_kg is None and per_unit and piece:
            per_kg, method = per_unit / piece * 1000, "pièce"
        if piece and per_unit is None and per_kg:
            per_unit = per_kg * piece / 1000
        priced[entry["id"]] = (per_kg, entry.get("yield", 1.0))
        observed = observed_packs(entry, selected)
        if observed:
            packs[entry["id"]] = observed
        report.append((entry["id"], per_kg, method, count, per_unit, unit_count, entry.get("packs", []), observed))

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
                foods[str(code)] = [round(per_kg, 2) if per_kg else None, yield_, entry["id"]]
                break
    for entry in entries:
        if not any(any(re.search(p, norm(f[1])) for p in entry["ciqual"]) for f in ciqual):
            unmatched.append(entry["id"])

    groups = {}
    by_group = {}
    for code, name, group, *_ in ciqual:
        if str(code) in foods and foods[str(code)][0]:
            by_group.setdefault(group, []).append(foods[str(code)][0])
    for group, values in by_group.items():
        values.sort()
        groups[group] = [round(values[int(len(values) * q)], 2) for q in (0.1, 0.5, 0.9)]

    out = {
        "source": "Open Prices (Open Food Facts), ODbL — prix France (médiane) relevés au " + datetime.date.today().isoformat(),
        "columns": ["eur_per_kg", "edible_yield", "product"],
        "foods": foods, "groups": groups,
        # Produit acheté en magasin (liste de courses) : libellé, unité d'achat (g, ml, piece), poids d'une pièce, rayon,
        # Prix : € par kg (par L) acheté, ou par pièce ; paquets en g, ml ou pièces ; périssable une fois ouvert.
        "products": {e["id"]: [e["label"], "piece" if e.get("piece") else e.get("unit", "g"), e.get("piece", 0), e["aisle"],
                               product_price(e, priced[e["id"]][0]), packs.get(e["id"], e.get("packs", [])),
                               1 if e.get("perishable") else 0]
                     for e in entries},
    }
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(out, handle, ensure_ascii=False, separators=(",", ":"))
    for item in report:
        print("%-24s %8s €/kg  %-12s n=%-4d pièce=%s (n=%d)  formats %s -> %s" % (
            item[0], f"{item[1]:.2f}" if item[1] else "-", item[2], item[3],
            f"{item[4]:.2f}" if item[4] else "-", item[5], item[6], item[7] or "inchangés"))
    print("Ciqual couverts :", len(foods), "· entrées sans aliment Ciqual :", unmatched, file=sys.stderr)


if __name__ == "__main__":
    main(*sys.argv[1:5])
