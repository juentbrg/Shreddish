# Feature Specification: Protéines par dose des compléments

**Feature Branch**: `007-supplement-servings`

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: « Pour la whey, pouvoir préciser le nombre de g de protéines par scoop : la mienne
c'est 24 g, il y en a de plus élevées, de plus faibles. »

Suite : « Il manque glucides, lipides et kcal pour la whey ; pour la créatine, "protéines par dose" n'a pas de
sens : adapter à chaque complément. »

## Requirements *(mandatory)*

- **FR-601**: Chaque complément a une nature : « apporte des macros » (whey, caséine, gainer, barres) ou « dose
  simple » (créatine, vitamines, oméga-3…), déduite du nom et modifiable.
- **FR-602**: Macros : taille de dose (g), kcal, protéines, glucides, lipides par dose. Dose simple : quantité
  par prise, unité (g, mg, µg, ml, gélule, comprimé, sachet), prises par jour. Résumé sous le nom.
- **FR-604**: `owned_supplements` envoyé en objets `{name, kind, serving_g?, kcal_per_serving?,
  protein_g_per_serving?, carbs_g_per_serving?, fat_g_per_serving?, dose?, doses_per_day?}` ; macros calculées
  au prorata de la dose ; dose simple sans macro, prise placée dans les étapes d'un repas.
- **FR-603**: Détail stocké par nom normalisé (`supplementInfoData`), effacé quand vide ; migration légère
  V5 → V6 (`Preferences` V5 figées).
