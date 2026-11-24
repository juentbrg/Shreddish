# Spec 018 : prix et formats calculés par l'application

## Problèmes
- Prix encore sous le ticket réel : médiane des relevés, tirée vers le bas par les discounters.
- Formats de `foods.json` écrits à la main, souvent faux (thon 140/420 g, cuisses de poulet 500 g).
- Prompt chargé : 27 prix de référence, liste des formats, règles de calcul de `unit_price_eur` et `cost_eur`.
- Budget contrôlé sur le coût estimé par l'IA, puis recalculé autrement par l'application.

## Exigences
- FR-1801 : prix d'un aliment = 3e quartile (moyen-haut) des relevés Open Prices sur 12 mois, vrac et paquets aux
  formats courants (± 10 %) seulement : sans sachets micro-ondes, frais traiteur ni mini-formats.
- FR-1802 : formats vendus = tailles les plus relevées des produits emballés de l'aliment (3 au plus, ≥ 3 relevés et
  10 % des relevés), entre 0,5 et 2 fois les formats de `foods.json` ; légumes frais et produits à la pièce : formats
  de `foods.json`.
- FR-1803 : l'IA n'envoie plus de prix (schéma sans `unit_price_eur` ni `cost_eur`) et ne reçoit plus
  `reference_prices_eur_per_kg` ni `pack_sizes`. Le prompt garde le budget comme objectif et la consigne de finir
  les paquets entamés.
- FR-1804 : aliment absent de la table : médiane de son groupe Ciqual, sinon médiane des produits de son rayon.
- FR-1805 : période au-dessus du plafond (coût calculé) : les jours les plus chers, assez pour combler l'écart, sont
  régénérés une fois avec leurs 3 ingrédients les plus chers ; gardés s'ils coûtent moins sans s'écarter des cibles
  (+0,15 au plus) ni répéter plus de plats. Jours avec une recette sauvegardée gardés. Jour régénéré au-dessus de sa
  part du budget : même essai.

## Hors champ
- Scan du ticket de caisse : option future, jamais obligatoire.
- Prix par enseigne.
