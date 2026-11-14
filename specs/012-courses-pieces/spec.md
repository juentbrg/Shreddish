# Spec 012 : liste de courses par produit acheté

## Problème
Œufs en trois lignes (« Oeufs », « Oeufs entiers », « Oeuf entier cru » en g) et rangés en crèmerie ;
bananes et pommes en double (g et pièces) ; avocat en grammes alors qu'il s'achète à la pièce ; huile de colza
en double (g et ml).

## Règle
Chaque ingrédient est rattaché au produit acheté en magasin, puis la liste fusionne par produit, dans l'unité
d'achat du produit.

## Exigences
- FR-1201 : chaque entrée de `tools/prices/foods.json` décrit un produit : libellé, rayon, unité d'achat
  (g par défaut, ml pour les liquides, pièce si `piece` donne le poids d'une pièce).
- FR-1202 : `prices.json` rattache chaque aliment Ciqual à son produit (`foods` : prix, part mangée, produit)
  et liste les produits (`products`).
- FR-1203 : quantité achetée = g mangés ÷ part mangée (peau, noyau, cuisson : riz cuit ramené au riz sec),
  puis ÷ poids d'une pièce pour un produit à la pièce ; une pièce déclarée compte pour une pièce.
- FR-1204 : pièces arrondies à l'unité supérieure, marge de 0,15 pièce ; g et ml à l'unité.
- FR-1205 : rattachement par code Ciqual, sinon par nom exact du produit (plans antérieurs à la spec 010).
- FR-1206 : sans produit connu, fusion par nom, g et ml confondus (1 ml = 1 g, affiché en ml).
- FR-1207 : listes existantes reconstruites au lancement si leurs lignes diffèrent (coches gardées par clé).
