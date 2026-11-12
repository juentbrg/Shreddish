# Feature Specification: Shreddish — planificateur de repas selon objectif

**Feature Branch**: `001-shreddish-meal-planner`

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "App iOS Haneal (Handled + Meal) — renommée Shreddish le 2026-11-12 —, usage personnel pour préparer une sèche.
Suggestion par IA de repas simples, pas chers, rapides à préparer. Organisation de la semaine selon
l'objectif (sèche, prise de masse, recomposition), avec calculateur basé sur taille, poids, genre,
âge, etc. Clé API GPT fournie par l'utilisateur."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Calculer ses besoins selon l'objectif (Priority: P1)

L'utilisateur saisit son profil (genre, âge, taille, poids, niveau d'activité) et choisit un
objectif : sèche, prise de masse ou recomposition. L'app affiche sa dépense estimée, sa cible
calorique quotidienne et sa répartition en protéines, glucides, lipides, avec l'explication du
calcul (dépense de base, activité, ajustement objectif).

**Why this priority**: Socle de tout le reste. Utile seul : l'utilisateur connaît ses cibles
pour sa sèche même sans planning.

**Independent Test**: Saisir un profil de référence, vérifier que cibles et macros correspondent
aux valeurs attendues des formules retenues.

**Acceptance Scenarios**:

1. **Given** aucun profil, **When** premier lancement, **Then** saisie du profil guidée avant
   tout autre écran.
2. **Given** profil complet et objectif « sèche », **When** validation, **Then** cible calorique
   inférieure à la dépense estimée, protéines élevées, détail du calcul visible.
3. **Given** profil existant, **When** modification du poids ou de l'objectif, **Then** cibles
   recalculées immédiatement.
4. **Given** valeur hors bornes (ex. taille 30 cm), **When** validation, **Then** refus avec
   message explicite.

---

### User Story 2 - Générer un planning de repas de la semaine (Priority: P2)

À partir de ses cibles, l'utilisateur demande un planning sur 7 jours. L'IA propose des repas
simples, bon marché, rapides à préparer, avec ingrédients, quantités, étapes courtes, temps de
préparation, coût estimé et valeurs nutritionnelles. Chaque journée affiche son total face à
la cible.

**Why this priority**: Cœur de la valeur : ne plus réfléchir à quoi manger pendant la sèche.

**Independent Test**: Avec un profil et une clé API valides, générer une semaine et vérifier
7 jours remplis, totaux journaliers proches de la cible, chaque repas sous le temps max.

**Acceptance Scenarios**:

1. **Given** cibles calculées et clé API valide, **When** demande de planning, **Then** 7 jours
   générés, chaque jour avec le nombre de repas configuré.
2. **Given** planning généré, **When** consultation d'un jour, **Then** total kcal et macros du
   jour affichés avec écart à la cible.
3. **Given** planning généré, **When** fermeture puis réouverture de l'app, **Then** planning
   toujours présent, sans nouvel appel IA.
4. **Given** aucune clé API, **When** demande de planning, **Then** invitation à saisir la clé,
   calculateur toujours accessible.

---

### User Story 3 - Ajuster le planning (Priority: P3)

Un repas ne plaît pas ou un ingrédient manque : l'utilisateur remplace ce repas seul par une
alternative aux macros équivalentes, ou régénère une journée entière, sans toucher au reste.

**Why this priority**: Rend le planning réellement suivable dans la durée.

**Independent Test**: Sur un planning existant, remplacer un repas et vérifier que seul ce repas
change et que le total du jour reste proche de la cible.

**Acceptance Scenarios**:

1. **Given** planning existant, **When** « remplacer » sur un repas, **Then** nouvelle
   proposition aux kcal proches, autres repas inchangés.
2. **Given** planning existant, **When** « régénérer la journée », **Then** seule cette journée
   change.

---

### User Story 4 - Journal alimentaire (Priority: P4)

Au fil de la journée, l'utilisateur marque les repas du planning comme mangés ou sautés et
ajoute les extras (écart, collation imprévue) avec leurs kcal et macros. L'app affiche le
réel face au prévu et à la cible, au jour et à la semaine.

**Why this priority**: Une sèche réussie dépend de l'adhérence réelle, pas du plan seul.

**Independent Test**: Sur une journée planifiée, marquer 2 repas mangés, 1 sauté, ajouter
1 extra ; vérifier le bilan réel.

**Acceptance Scenarios**:

1. **Given** journée planifiée, **When** repas marqué « mangé », **Then** ses valeurs comptent
   dans le bilan réel.
2. **Given** journée planifiée, **When** ajout d'un extra de 300 kcal, **Then** bilan réel
   augmenté de 300 kcal, écart à la cible mis à jour.
3. **Given** semaine terminée, **When** consultation du bilan hebdo, **Then** moyenne kcal /
   macros et taux d'adhérence (repas mangés / prévus) affichés.

---

### User Story 5 - Liste de courses de la semaine (Priority: P5)

À partir du planning, l'app agrège tous les ingrédients en une liste de courses regroupée par
rayon, avec quantités cumulées et coût total estimé. Éléments cochables en magasin.

**Why this priority**: Gros gain de temps et de budget, mais dépend du planning.

**Independent Test**: Générer la liste depuis un planning connu, vérifier les quantités cumulées.

**Acceptance Scenarios**:

1. **Given** planning de 7 jours, **When** ouverture de la liste, **Then** ingrédients
   identiques fusionnés, quantités additionnées.
2. **Given** liste ouverte, **When** cocher un élément, **Then** état conservé après fermeture.

---

### User Story 6 - Suivre son poids et réajuster (Priority: P6)

L'utilisateur enregistre son poids (ex. une fois par semaine). L'app affiche l'évolution et
propose de recalculer les cibles avec le nouveau poids.

**Why this priority**: Une sèche dure des semaines ; les cibles doivent suivre le poids.

**Independent Test**: Saisir plusieurs pesées, vérifier courbe et proposition de recalcul.

**Acceptance Scenarios**:

1. **Given** nouvelle pesée, **When** enregistrement, **Then** historique mis à jour et
   proposition de recalcul des cibles.
2. **Given** perte supérieure à 1 % du poids par semaine en sèche, **When** consultation,
   **Then** alerte rythme trop rapide.

---

### Edge Cases

- Réponse IA invalide, incomplète ou hors cible (écart journalier > 10 %) : rejet ou
  signalement, aucune donnée corrompue enregistrée, nouvel essai proposé.
- Pas de réseau ou clé invalide / quota épuisé : message clair, planning existant intact.
- Cible calorique calculée sous un plancher de sécurité : cible ramenée au plancher, avertissement.
- Préférences trop restrictives (ex. allergies multiples + budget très bas) : IA signale
  l'impossibilité plutôt que d'ignorer une contrainte.
- Génération interrompue (app fermée) : ancien planning conservé.

## Requirements *(mandatory)*

### Functional Requirements

**Profil et calculateur**

- **FR-001**: Le système MUST collecter genre, âge, taille (cm), poids (kg), niveau d'activité
  (5 niveaux, de sédentaire à très actif) et objectif (sèche, prise de masse, recomposition).
- **FR-002**: Le système MUST calculer métabolisme de base, dépense journalière totale, cible
  calorique selon objectif et répartition protéines / glucides / lipides en grammes et kcal.
- **FR-003**: Ajustements par défaut : sèche ≈ −20 % de la dépense, prise de masse ≈ +10 %,
  recomposition ≈ maintien ; protéines ≈ 2 g/kg en sèche et recomposition, ≈ 1,8 g/kg en
  prise de masse ; lipides 0,8 g/kg par défaut, jamais sous 0,6 g/kg (abaissés jusqu'à 0,6
  seulement si les glucides deviennent négatifs, avec alerte) ; glucides = reste. Valeurs
  modifiables par l'utilisateur dans ces bornes.
- **FR-004**: Le système MUST appliquer un plancher calorique de sécurité et avertir lorsqu'il
  s'applique.
- **FR-005**: Le système MUST afficher le détail du calcul et la mention « outil personnel, pas
  un avis médical ».
- **FR-006**: Le système MUST valider les bornes des saisies (âge 16–90, taille 120–230 cm,
  poids 35–250 kg).

**Préférences**

- **FR-007**: L'utilisateur MUST pouvoir définir : nombre de repas par jour (2 à 5, collations
  incluses), temps de préparation max par repas, budget indicatif par jour, aliments exclus /
  allergies, aliments appréciés, équipement disponible.
- **FR-008**: Valeurs par défaut : 4 repas / jour (3 repas + 1 collation), 20 min max,
  budget 8 € / jour.

**Planning**

- **FR-009**: Le système MUST générer via IA un planning de 7 jours consécutifs, du jour de
  la génération (inclus) à J+6, respectant cibles et préférences. Coût d'un jour au-delà de
  110 % du budget journalier : jour signalé.
- **FR-010**: Chaque repas MUST comporter : nom, ingrédients avec quantités, étapes courtes,
  temps de préparation, coût estimé, kcal et macros.
- **FR-011**: Le système MUST recalculer localement les totaux journaliers à partir des valeurs
  des repas et afficher l'écart à la cible ; un jour à plus de 10 % d'écart est signalé.
- **FR-012**: Le système MUST permettre de remplacer un repas seul ou de régénérer une journée.
- **FR-013**: Le système MUST conserver le planning courant et les plannings précédents
  consultables hors ligne.
- **FR-014**: Le système MUST proposer un réglage « batch cooking » (désactivé par défaut).
  Actif : l'IA mutualise des préparations sur plusieurs repas (ex. riz + poulet pour 3 repas)
  et le planning inclut 1 à 2 sessions de préparation avec étapes et durée. Inactif : chaque
  repas est indépendant.

**Courses**

- **FR-015**: Le système MUST produire une liste de courses agrégée par rayon depuis le planning,
  avec quantités cumulées, coût total estimé et cases à cocher persistantes.

**Suivi**

- **FR-016**: L'utilisateur MUST pouvoir enregistrer son poids daté et voir l'historique.
- **FR-017**: Après une pesée, le système MUST proposer le recalcul des cibles.
- **FR-018**: L'utilisateur MUST pouvoir marquer chaque repas du planning « mangé » ou
  « sauté », et ajouter des extras libres (nom, quantité, kcal, macros) à une journée.
- **FR-018b**: Le système MUST afficher le bilan réel du jour (repas mangés + extras) face à la
  cible et au prévu, et un bilan hebdomadaire (moyenne kcal / macros, taux d'adhérence).

**IA et clé API**

- **FR-019**: L'utilisateur MUST pouvoir saisir, tester, remplacer et supprimer sa clé API ;
  clé stockée de façon sécurisée sur l'appareil, jamais affichée en clair après saisie.
- **FR-020**: Appels IA seulement sur action explicite ; aucune génération automatique en tâche
  de fond.
- **FR-021**: Données envoyées à l'IA limitées aux cibles, préférences et contraintes ; aucune
  donnée d'identité.

### Key Entities

- **Profil** : genre, âge, taille, poids courant, niveau d'activité, objectif, réglages macros.
- **Cibles nutritionnelles** : kcal, protéines, glucides, lipides par jour ; dérivées du profil.
- **Préférences** : repas par jour, temps max, budget, exclusions, goûts, équipement.
- **Planning hebdomadaire** : date de début (jour de génération), 7 journées consécutives, cibles utilisées lors de la génération.
- **Journée** : date, liste de repas, totaux calculés, écart à la cible.
- **Repas** : type (petit-déj, déjeuner, dîner, collation), nom, ingrédients, étapes, temps,
  coût, kcal, macros.
- **Ingrédient** : nom, quantité, unité, rayon, coût estimé.
- **Liste de courses** : dérivée d'un planning ; éléments agrégés avec état coché.
- **Pesée** : date, poids.
- **Entrée de journal** : journée, repas du planning (mangé / sauté) ou extra libre (nom,
  quantité, kcal, macros).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Profil saisi et cibles obtenues en moins de 2 minutes au premier lancement.
- **SC-002**: Cibles calculées identiques (±1 kcal) aux valeurs de référence des formules
  retenues sur 100 % des profils de test.
- **SC-003**: Planning de 7 jours obtenu en moins de 60 secondes après la demande.
- **SC-004**: Au moins 90 % des journées générées à ±10 % de la cible calorique.
- **SC-005**: 100 % des repas proposés respectent le temps de préparation max et les exclusions.
- **SC-006**: Coût hebdo estimé du planning ≤ budget défini dans au moins 90 % des générations.
- **SC-007**: Remplacement d'un repas en moins de 15 secondes.
- **SC-008**: Usage réel : planning suivi au moins 5 jours sur 7 pendant les 4 premières
  semaines de sèche.

## Assumptions

- Un seul utilisateur, un seul iPhone ; ni compte, ni synchronisation, ni partage.
- Connexion réseau requise seulement pour la génération IA ; tout le reste fonctionne hors ligne.
- Coûts estimés indicatifs (prix moyens France, supermarché classique), pas de prix réels
  d'enseigne.
- Valeurs nutritionnelles des repas : estimations de l'IA, contrôlées par cohérence
  (kcal ≈ 4 × protéines + 4 × glucides + 9 × lipides), sans base de données nutritionnelle
  officielle en v1.
- Formule de dépense de base : Mifflin-St Jeor (référence courante) ; facteurs d'activité
  standards 1,2 à 1,9.
- Unités métriques uniquement ; interface en français.
- Pas d'intégration Apple Santé en v1.
- Coût d'appel IA à la charge de l'utilisateur via sa propre clé.
