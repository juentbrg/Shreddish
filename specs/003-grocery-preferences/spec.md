# Feature Specification: Préférences de courses

**Feature Branch**: `003-grocery-preferences`

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: « Pour la génération des repas / liste de courses, pouvoir choisir des
options : budget courses de la semaine, dépassement léger autorisé (genre +10 %), allergies, aliments
qu'on n'aime pas. L'IA ne doit prendre que des ingrédients trouvables quasiment partout, pas des trucs
de niche ; paramétrable. Idéalement, choisir le magasin pour des prix réalistes. »

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Budget de la semaine avec tolérance (Priority: P1)

L'utilisateur fixe un budget courses hebdomadaire et un dépassement toléré (0 à 20 %). Un planning
au-delà du budget + tolérance est refusé et regénéré ; entre budget et tolérance, il est accepté et
signalé. La liste de courses affiche le total face au budget.

**Independent Test**: Budget 56 €, planning à 57,40 € : refusé à 0 %, accepté et signalé à 5 %.

**Acceptance Scenarios**:

1. **Given** budget 56 € et tolérance 0 %, **When** planning à 57,40 €, **Then** rejet et nouvel essai.
2. **Given** tolérance 5 % (plafond 58,80 €), **When** planning à 57,40 €, **Then** accepté, signalé.
3. **Given** régénération d'un jour, **When** calcul, **Then** budget du jour = plafond semaine − coût
   des 6 autres jours.

### User Story 2 - Allergies et aliments refusés (Priority: P1)

Deux listes distinctes : allergies (jamais, traces comprises) et aliments que l'utilisateur n'aime pas
(jamais). Toute présence rejette le planning.

**Independent Test**: Allergie « arachide », repas avec « beurre de cacahuète » non détecté par le
nom → l'IA est prévenue ; repas avec « arachides grillées » → rejet.

### User Story 3 - Ingrédients courants et magasin (Priority: P2)

L'utilisateur choisit la disponibilité des ingrédients (partout y compris hard discount / grand
supermarché / magasins spécialisés acceptés) et son magasin habituel. L'IA n'utilise que des produits
vendus dans ce magasin et estime les prix de cette enseigne, marque distributeur en priorité.

**Independent Test**: Magasin « Lidl », disponibilité « partout » → consigne transmise à l'IA ;
écran préférences affiche le choix ; prix annoncés comme estimations.

### Edge Cases

- Préférences existantes : budget hebdo = budget jour × 7, tolérance 10 %, disponibilité
  « partout », magasin « supermarché classique » ; anciens aliments exclus → « n'aime pas ».
- Budget impossible à tenir : l'IA renseigne `infeasible`, raison affichée.
- Magasin « Autre » : nom libre transmis tel quel.

## Requirements *(mandatory)*

- **FR-201**: Budget hebdo 20 à 300 €, pas de 5 € ; tolérance 0, 5, 10, 15 ou 20 % (défaut 10 %).
- **FR-202**: Coût semaine > budget × (1 + tolérance) : rejet (nouvel essai) ; > budget : signalé.
- **FR-203**: Jour régénéré : plafond = budget × (1 + tolérance) − coût des autres jours ; repas
  remplacé : plafond = plafond du jour − coût des autres repas du jour. Dépassement : rejet.
- **FR-204**: Allergies et aliments refusés en listes séparées, tous deux bloquants ; consigne IA
  « allergies : aucune trace, attention aux dérivés ».
- **FR-205**: Disponibilité : partout (dont Lidl / Aldi), grand supermarché, spécialisé accepté
  (défaut : partout). Consigne IA associée.
- **FR-206**: Magasin : supermarché classique (défaut), Lidl, Aldi, Leclerc, Intermarché, Carrefour,
  Carrefour Market, Auchan, Super U, Monoprix, Franprix, Autre (nom libre). Consigne IA : produits
  de l'enseigne, prix de l'enseigne, marque distributeur en priorité.
- **FR-207**: Liste de courses : total, budget, tolérance, écart.
- **FR-208**: Migration sans perte (FR-111).
- **FR-209**: Prix toujours présentés comme estimations : aucune base de prix réelle (constitution I,
  pas de backend).

## Success Criteria *(mandatory)*

- **SC-201**: 100 % des plannings enregistrés ≤ budget × (1 + tolérance), selon les prix estimés.
- **SC-202**: 0 repas avec allergène ou aliment refusé listé.

## Assumptions

- Prix estimés par l'IA d'après sa connaissance des enseignes françaises ; pas de prix temps réel.
- Le coût d'un ingrédient est celui de la quantité utilisée (comme spec 001).
