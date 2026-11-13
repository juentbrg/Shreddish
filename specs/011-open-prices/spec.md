# Spec 011 : prix France Open Prices, sans magasin ni ville

## Problèmes (tests sur iPhone, spec 010)
- Prix inventés par l'IA, trop bas (filet de poulet 6,5 à 8 €/kg, magret 4,30 €) et instables d'une semaine à l'autre (fromage blanc 0 % de 1,48 à 11,67 €/kg).
- Coût calculé sur la part mangée : peau, noyau et jus des conserves non payés (180 g d'avocat à 0,82 €).
- Choix du magasin et de la ville sans effet fiable sur les prix.

## Exigences
- FR-1101 : table de prix embarquée (`Resources/prices.json`), générée hors ligne par `tools/prices/build_prices.py` depuis l'export Open Prices (Open Food Facts, ODbL) : prix France, hors promotions, au kg acheté (au litre pour les liquides), par code Ciqual.
- FR-1102 : prix d'un aliment = quartile bas des relevés des 12 derniers mois dès 8 relevés ; sinon fenêtre de 24 mois et moyenne des médianes par enseigne.
- FR-1103 : part comestible par aliment (avocat 0,7, banane 0,65, conserves égouttées 0,6 à 0,75) ; aliment Ciqual cuit : prix ramené au poids cuit (riz, pâtes, légumineuses, viandes).
- FR-1104 : l'app recalcule le prix de chaque ingrédient rapproché de Ciqual ; aliment sans prix : prix de l'IA borné aux 10e et 90e centiles de son groupe Ciqual ; sans rapprochement : prix de l'IA. Compléments possédés : coût 0.
- FR-1105 : le prompt reçoit les prix de référence de 27 aliments courants (`reference_prices_eur_per_kg`) pour estimer le budget comme l'app.
- FR-1106 : choix du magasin et ville retirés (réglages, prompt, liste de courses) ; champs gardés en base pour la migration.
- FR-1107 : crédit Open Prices (ODbL) dans « À propos ».

## Hors champ
- Liste de courses en emballages entiers : stock d'une semaine sur l'autre, coût trompeur.
