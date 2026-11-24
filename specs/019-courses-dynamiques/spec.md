# Spec 019 : liste de courses dynamique, puis validée

## Problème
Semaine entamée avant les courses : la liste garde les ingrédients des repas déjà mangés.

## Exigences
- FR-1901 : tant que les courses d'un planning ne sont pas validées, la liste ne compte que les repas prévus
  (repas mangés ou sautés retirés). Recalcul au lancement et à l'ouverture de l'onglet Courses ; coches gardées.
- FR-1902 : tout coché → « Valider les courses » : liste figée telle qu'achetée (`ShoppingValidation`, SchemaV14) ;
  « Rouvrir » la rend de nouveau dynamique.
- FR-1903 : plannings terminés ou en historique : courses figées automatiquement au lancement (restes reportés sur
  la semaine suivante conservés).
- FR-1904 : coût de la semaine face au budget : tous les repas, mangés compris.

## Hors champ
- Ingrédients à écouler consommés par un repas mangé : toujours déduits de la liste.
