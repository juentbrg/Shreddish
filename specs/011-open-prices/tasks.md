# Tâches spec 011
- [x] T1101 `tools/prices/foods.json` (correspondance aliments Ciqual ↔ catégories Open Prices), `build_prices.py`, `Resources/prices.json` (659 aliments Ciqual, 13 Ko)
- [x] T1102 `PriceCatalog` : prix au kg mangé, pièces au poids, prix de l'IA borné par groupe
- [x] T1103 `NutritionResolver.priced`, coût des repas recalculé ; huile ajoutée au prix de la table
- [x] T1104 Prompt : règle de prix France, `reference_prices_eur_per_kg` ; magasin et ville retirés
- [x] T1105 UI : réglages sans magasin ni ville, mention « Prix moyens en France », crédit Open Prices
- [x] T1106 Tests : prix de la table, part comestible, poids cuit, prix borné, pièces ; tests de budget adaptés
- [x] T1107 Essais réels : semaine à 44,78 et 48,27 € (contre 27 à 37 € avant), 93 % des lignes au prix de la table, macros inchangées (±8 %)
