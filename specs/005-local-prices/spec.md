# Feature Specification: Prix par enseigne et secteur

**Feature Branch**: `005-local-prices`

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: « La sélection du magasin ne change pas grand-chose aux prix. Si on ne peut
pas la rendre exploitable, autant la virer, sinon on le fait bien. Pouvoir choisir sa localisation :
les prix ne sont pas les mêmes à Toulouse qu'à Luchon. Pas d'appareil photo : que GPT fasse une
estimation réaliste sur le secteur. »

## Research

- Aucune API publique de prix des enseignes françaises (drives sans API, scraping hors CGU).
- Open Prices (Open Food Facts) : ~100 prix sur 12 mois dans 10 km autour de Toulouse, 5 prix au
  total autour de Luchon, filtre par enseigne inopérant : inexploitable (relevé du 2026-11-12).
- Décision : estimation par l'IA, mais structurée : prix unitaire (€/kg, €/L, €/pièce) par ingrédient
  pour l'enseigne et le secteur, coût calculé par l'app (constitution II).

## Requirements *(mandatory)*

- **FR-401**: Champ « Ville » (optionnel) dans « Où tu fais tes courses » ; vide = France.
- **FR-402**: L'IA renvoie `unit_price_eur` par ingrédient ; l'app calcule coût ingrédient =
  quantité × prix unitaire (÷ 1000 pour g et ml) et coût du repas = somme des ingrédients.
- **FR-403**: Prompt : positionnement de l'enseigne et du secteur (grande ville moins chère, petite
  ville, montagne ou zone touristique plus chère).
- **FR-404**: Migration légère V4 → V5 sans perte (`Preferences` V4 figées).
