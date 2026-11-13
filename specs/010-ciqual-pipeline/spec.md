# Spec 010 : macros Ciqual, portions ajustées, recettes en arrière-plan

## Problèmes (tests réels, spec 009)
- Macros des repas inventées par l'IA (cible recopiée) : écarts invisibles.
- Quantités absurdes acceptées (« 150 œufs », semaine à 4 748 €).
- Semaine répétitive acceptée (4 plats sur 28).
- Réponse unique très longue : refus, lenteur (60 à 150 s).

## Exigences
- FR-1001 : table Ciqual 2025 (ANSES, Etalab 2.0) embarquée, réduite à code, nom, groupe, kcal, protéines, glucides, lipides pour 100 g (`tools/ciqual/build_catalog.py`).
- FR-1002 : l'IA choisit librement ses ingrédients. L'app rapproche chaque nom d'un aliment Ciqual : index local ; candidats proches aux macros semblables = rapprochement sûr ; sinon un seul appel IA groupé choisit parmi 5 candidats. Correspondances mémorisées sur l'appareil.
- FR-1003 : macros d'un repas = somme Ciqual de ses ingrédients ; ingrédient non trouvé = repas gardé avec les macros de l'IA, signalé.
- FR-1004 : pièces converties en grammes avec `piece_g` fourni par l'IA.
- FR-1005 : portions ajustées par l'app pour atteindre les cibles du jour (sources de protéines, féculents, matières grasses ; facteur 0,6 à 1,6 ; légumes, pièces et compléments fixes). Jour hors cible après ajustement : une seule régénération avec retour chiffré.
- FR-1006 : garde-fous fatals (nouvel essai) : plus de 12 pièces ou 2 kg d'un ingrédient dans un repas, prix aberrant (> 80 € le kg ou litre, > 10 € la pièce), semaine > 3 × plafond budget, même déjeuner ou dîner plus de 2 fois (hors batch cooking ; petit-déjeuner et collations libres).
- FR-1007 : semaine générée sans étapes ; recettes générées en arrière-plan (4 en parallèle) et enregistrées ; repas ouvert avant sa recette = généré en priorité. Prises de compléments « dose » (créatine…) ajoutées par l'app à la recette du repas choisi (le plus proche après l'entraînement, sinon le déjeuner).
- FR-1008 : remplacement d'un repas : recette incluse, macros Ciqual, portions ajustées aux macros restantes du jour.
