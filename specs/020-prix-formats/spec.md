# Spec 020 : prix médians, formats réels, doublons fusionnés

Contexte : comparaison du 2026-11-25 d'une semaine générée avec les prix des magasins (Open Prices, Monoprix) :
23 articles sur 28 au bon niveau, mais 3 trop chers (épinards surgelés, flocons d'avoine, tomates en conserve),
2 formats introuvables en rayon (huile de colza 75 cl, pâtes 250 g) et des doublons (« Mélange de légumes
surgelés » à côté de « Légumes surgelés »).

- FR-2001 : prix d'un aliment = médiane des relevés Open Prices sur 12 mois (au lieu du 3e quartile de la
  spec 018) ; repli par enseigne sur 24 mois, moyenne des médianes.
- FR-2002 : formats vendus = ceux de `tools/prices/foods.json`, relevés à la main en rayon ; chacun est calé sur
  la taille la plus relevée à moins de 8 % (thon 140 g). Une taille relevée hors de ces formats est ignorée :
  elle vient surtout de produits voisins (pâtes aux œufs, huile vierge).
- FR-2003 : plusieurs formats par produit (riz 500 g, 1 kg, 2 kg) ; la liste combine les formats : quantité
  achetée minimale, puis le moins de paquets, puis les plus grands formats (1 100 g de riz : 1 kg + 500 g).
  Affichage « 1 × 1 kg + 1 × 500 g ».
- FR-2004 : un ingrédient sans produit rattaché par son code Ciqual l'est par son nom exact, sinon par mots :
  produit dont tous les mots de l'identifiant figurent dans le nom, le plus précis puis celui nommé en premier
  (« Tomates concassées en conserve » → Tomates en conserve, « Compote de pommes » → Compote). Pas de
  rattachement par mots pour un nom cuit (poids acheté inconnu).
- FR-2005 : à la reconstruction d'une liste, les coches suivent la nouvelle clé de l'article ; une ligne
  fusionnée n'est cochée que si tous ses anciens articles l'étaient. Liste validée : inchangée (spec 019).
