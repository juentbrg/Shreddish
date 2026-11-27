# Spec 014 : recettes sauvegardées, replacées dans une semaine suivante

Rédigée a posteriori le 2026-11-27 d'après le code.

## Problème
Un repas qui a plu disparaît avec son planning ; impossible de le redemander à l'IA la semaine suivante.

## Exigences
- FR-1401 : signet dans la fiche d'un repas : « Sauvegarder la recette » / « Retirer des recettes » ; désactivé
  tant que la recette n'est pas rédigée. Rapprochement par nom normalisé (singulier).
- FR-1402 : recette sauvegardée = copie du repas (`SavedRecipe`, SchemaV8, migration légère depuis V7) : type,
  nom, ingrédients, étapes, temps, coût, macros, date ; survit à la suppression du planning.
- FR-1403 : onglet Recettes : grille triée de la plus récente à la plus ancienne, recherche par nom, filtre
  Toutes / Matin / Midi, soir / Collations ; carte : kcal, prix, macros P · G · L.
- FR-1404 : fiche d'une recette : ingrédients, étapes, interrupteur « Pour la semaine prochaine » (`isQueued`,
  badge « Semaine pro. » sur la carte, compteur en tête de liste) ; retrait avec confirmation, ou par menu contextuel.
- FR-1405 : feuille « Planifier » : section « Recettes à replacer » si au moins une recette sauvegardée ;
  cochées par défaut celles mises en attente, sélection modifiable.
- FR-1406 : `recipes_to_include` envoyé à l'IA : type, nom, ingrédients (nom, quantité, unité), sans étapes.
  Règle du prompt : chacune placée une fois, à son type de repas, même nom et mêmes ingrédients, quantités
  ajustées aux cibles seulement si besoin.
- FR-1407 : repli jour par jour : la n-ième recette envoyée au jour n mod 7.
- FR-1408 : étapes de la recette reprises si le repas généré porte le même nom et les mêmes ingrédients
  (même unité, quantités à ±10 %) ; sinon rédigées pour les nouvelles quantités.
- FR-1409 : génération réussie : recettes replacées retirées de l'attente ; échec : attente conservée.

## Hors champ
- Création et modification d'une recette à la main (spec 017).
