# Feature Specification: Activité détaillée et calibration par les pesées

**Feature Branch**: `002-activity-calibration`

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: « Je suis considéré comme modérément actif (3 à 5 fois par semaine) alors
que je fais 3 séances de musculation en surcharge progressive (échec sur tous les exos) et 2 séances
d'escalade par semaine. » → 1. séparer entraînement et activité quotidienne ; 2. recalculer la dépense
réelle à partir des pesées et du journal, avec ajustement automatique hebdomadaire.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Décrire son activité réelle (Priority: P1)

Au lieu d'un niveau d'activité unique, l'utilisateur indique son activité quotidienne hors sport
(métier, pas) et son entraînement : nombre de séances par semaine, durée moyenne, intensité. La
dépense est calculée à partir de ces deux parts, détaillées à l'écran.

**Why this priority**: Le niveau unique mélange sport et vie quotidienne ; 5 séances intenses et un
métier de bureau n'ont pas la même dépense qu'un métier physique sans sport.

**Independent Test**: Profil homme 30 ans, 180 cm, 80 kg, bureau, 5 séances × 75 min intenses,
sèche → dépense 2529 kcal, cible 2023 kcal, détail visible.

**Acceptance Scenarios**:

1. **Given** onboarding, **When** saisie activité quotidienne + séances + durée + intensité,
   **Then** cible calculée et détail : base × facteur quotidien + dépense sport par jour.
2. **Given** profil existant avec ancien niveau unique, **When** ouverture, **Then** cibles
   inchangées et invitation à préciser l'activité.
3. **Given** 0 séance, **When** calcul, **Then** dépense = base × facteur quotidien.

---

### User Story 2 - Calibration par les pesées (Priority: P2)

Avec au moins 2 semaines de pesées et 10 jours de journal complet sur les 4 dernières semaines, l'app
estime la dépense réelle (apport moyen + variation de poids) et ajuste la cible une fois par
semaine, par petits pas, si l'ajustement automatique est actif. L'utilisateur voit l'estimation,
l'écart avec la formule et l'état des données.

**Why this priority**: Toute formule se trompe de ±10–15 % ; la balance et le journal donnent la
vraie réponse au bout de quelques semaines.

**Independent Test**: 14 jours, 80 → 79 kg, 2000 kcal mangées par jour → dépense réelle estimée
2550 kcal ; ajustement appliqué de moitié, plafonné à 150 kcal par semaine.

**Acceptance Scenarios**:

1. **Given** données suffisantes et 7 jours depuis le dernier ajustement, **When** ouverture de
   l'app, **Then** ajustement appliqué et message « Cibles ajustées : X → Y kcal ».
2. **Given** données insuffisantes, **When** consultation, **Then** progression affichée
   (jours de journal complets, durée couverte par les pesées), aucun ajustement.
3. **Given** ajustement automatique désactivé, **When** ouverture, **Then** aucun ajustement ;
   bouton « Recalibrer maintenant » disponible.
4. **Given** estimation aberrante (< 60 % ou > 150 % de la formule), **When** calcul, **Then**
   rejet et message « journal probablement incomplet ».

### Edge Cases

- Jour partiellement journalisé (un repas encore « prévu ») : exclu de l'apport moyen.
- Deux plannings couvrant le même jour : journal du jour le plus renseigné.
- Prise de poids en sèche : dépense estimée sous l'apport, ajustement négatif.
- Ajustement cumulé limité à ±600 kcal ; réinitialisable.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-101**: Activité quotidienne : sédentaire (bureau, < 5 000 pas, ×1,2), légère (5 000 à 7 500,
  ×1,3), active (7 500 à 10 000, ×1,4), très active (> 10 000 pas ou métier physique, ×1,5).
- **FR-102**: Entraînement : 0 à 14 séances / semaine, 15 à 240 min, intensité légère (MET 3,5),
  modérée (MET 5), intense (MET 6,5 : muscu à l'échec, escalade, HIIT).
- **FR-103**: Dépense sport / séance = (MET − 1) × poids × durée (h) ; dépense = BMR × facteur
  quotidien + dépense sport hebdo / 7 + ajustement de calibration.
- **FR-104**: Profils existants sans ces champs : ancien facteur conservé, invitation à préciser.
- **FR-105**: Jour complet = au moins un repas, aucun repas au statut « prévu ».
- **FR-106**: Estimation si ≥ 10 jours complets et pesées couvrant ≥ 14 jours dans les 28 derniers
  jours (hier inclus, aujourd'hui exclu pour l'apport) ; pente du poids par régression linéaire ;
  dépense réelle = apport moyen − pente (kg/jour) × 7700.
- **FR-107**: Estimation rejetée hors [60 %, 150 %] de la dépense formule.
- **FR-108**: Nouvel ajustement = actuel + (cible − actuel) / 2, pas limité à ±150 kcal, total
  limité à ±600 kcal ; au plus une fois tous les 7 jours en automatique.
- **FR-109**: Réglages : ajustement automatique (actif par défaut), recalibrer maintenant,
  réinitialiser l'ajustement.
- **FR-110**: Détail du calcul : facteur quotidien, dépense sport / jour, ajustement de calibration.
- **FR-111**: Migration des données existantes sans perte (nouveau schéma).

### Key Entities

- **Profil** (ajouts) : activité quotidienne, séances / semaine, durée, intensité, ajustement de
  calibration (kcal), date du dernier ajustement, ajustement automatique.
- **Estimation de dépense** (dérivée) : dépense réelle, apport moyen, variation hebdo, jours
  complets, couverture des pesées.

## Success Criteria *(mandatory)*

- **SC-101**: Profil de référence (bureau, 5 × 75 min intenses) → 2529 kcal de dépense, ±1 kcal.
- **SC-102**: Après 4 semaines de journal et pesées, écart cible / dépense réelle < 5 %.
- **SC-103**: Aucune perte de données à la mise à jour.

## Assumptions

- 7700 kcal par kg de variation de poids (approximation standard).
- MET moyens par intensité, indépendants du sport exact.
- Le journal est la seule source d'apport ; jours hors planning ignorés.
