# Spec 013 : courses au prix réel

## Problème
Semaine estimée à 60 €, ticket réel de 80 €. Trois causes :
- quartile bas des relevés Open Prices : prix de discounter ;
- produits trop larges (« porc filet » mêlait filet mignon, échine et rôti : 8,55 €/kg contre 22 €/kg) ;
- conditionnement ignoré : 150 g de pois chiches comptés 150 g au lieu d'une boîte de 400 g, reste perdu.

## Exigences
- FR-1301 : prix = médiane des relevés sur 12 mois (repli inchangé) ; prix de repli saisi dans `foods.json`
  (`price`) quand moins de 8 relevés (filet mignon : surtout des plats préparés dans Open Prices).
- FR-1302 : filet mignon séparé du porc courant (rôti, côtes, échine).
- FR-1303 : chaque produit a ses formats vendus (`packs`, dans l'unité d'achat) et `perishable` (frais,
  conserve : se perd une fois ouvert). `prices.json` exporte prix d'achat, formats et périssabilité.
- FR-1304 : la liste achète des paquets entiers : un seul format, le moins de reste, puis le moins de paquets ;
  version surgelée d'un produit frais en sachets de 750 g ou 1 kg ; au détail sans format.
- FR-1305 : ticket estimé = prix des paquets ; coût de la semaine = ticket − restes qui se gardent ; restes
  périssables signalés (« à finir sous 3 jours ») et comptés comme dépensés. Le budget se compare au coût
  de la semaine.
- FR-1306 : l'IA reçoit `pack_sizes` (formats des produits périssables) et la consigne de finir chaque
  paquet ouvert sur des repas proches.
- FR-1307 : questionnaire facultatif avant la génération : « Des ingrédients à écouler ? » Non : génération
  telle quelle. Oui : liste éditable (nom, quantité, g/ml/pièce), pré-remplie avec les paquets entamés de la
  dernière liste. Envoyée à l'IA (`ingredients_to_use`), rapprochée de Ciqual, gardée sur le planning
  (SchemaV7, `WeeklyPlan.pantryData`) et déduite des courses (« Déjà chez toi »).

## Hors champ
- Absorption automatique des restes périssables par ajustement des portions (piste : PortionAdjuster).
- Prix par enseigne.
