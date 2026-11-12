# Feature Specification: Compléments, horaires, budget souple et recettes détaillées

**Feature Branch**: `004-supplements-recipes`

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: « Lister les compléments alimentaires qu'on possède pour que l'IA en tienne
compte dans les macros (soulager la forte demande en protéines) : si j'ai ma whey, elle doit me dire
quand et à quelle heure la prendre. Je vois 0 riz : sans cuiseur à riz, je le fais à la casserole.
Les glucides dépassent. À 80 € +15 %, génération refusée faute de budget, alors qu'à 300 € le planning
coûte 80,5 € : trop bloquant. À petit budget, il propose du skyr au lieu du yaourt 0 %. Recettes pas
détaillées, 5 étapes ne suffisent pas. Pouvoir supprimer un programme entier. »

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compléments possédés et horaires (Priority: P1)

L'utilisateur liste ses compléments (whey, créatine…) et son heure d'entraînement habituelle. L'IA les
intègre aux repas (macros comptées, coût 0 €), indique l'heure de chaque repas et le moment de prise.
Les compléments possédés n'apparaissent pas dans la liste de courses.

**Acceptance Scenarios**:

1. **Given** « Whey » possédée, **When** génération, **Then** la whey peut figurer dans un repas, son
   coût est ramené à 0 € et elle est absente de la liste de courses.
2. **Given** un repas, **When** affichage, **Then** son heure conseillée (HH:mm) est visible.
3. **Given** une heure invalide renvoyée par l'IA, **When** validation, **Then** heure ignorée.

### User Story 2 - Budget souple (Priority: P1)

Une semaine au-dessus du plafond (budget + tolérance) n'est plus bloquante : un nouvel essai est fait en
indiquant à l'IA le coût obtenu ; si le second reste au-dessus, le planning est accepté et signalé.
Même règle pour un jour régénéré ou un repas remplacé. À petit budget, l'IA choisit les produits les
moins chers par gramme de protéine (yaourt 0 %, fromage blanc, œufs, lentilles) et ne déclare jamais
« infeasible » pour le seul budget.

### User Story 3 - Recettes détaillées et féculents (Priority: P2)

Étapes détaillées (quantités, feu, durées, repères visuels), 4 à 12 selon le plat. Plaques, casserole,
poêle et four toujours disponibles : riz et pâtes à la casserole autorisés sans cuiseur. Glucides et
lipides à ±10 % de leur cible ; badge si glucides > +15 %.

### User Story 4 - Supprimer le planning courant (Priority: P2)

Menu de la semaine : « Supprimer ce planning », avec confirmation (journal des jours concernés supprimé).

## Requirements *(mandatory)*

- **FR-301**: Liste « Compléments possédés » avec suggestions, supprimable ; heure d'entraînement optionnelle.
- **FR-302**: Champ `time` (HH:mm ou null) par repas, stocké et affiché.
- **FR-303**: Ingrédient correspondant à un complément possédé : coût 0, retiré de la liste de courses.
- **FR-304**: Plafond budget dépassé → avertissement après un nouvel essai, plus d'échec.
- **FR-305**: Règles de prompt : petit budget, féculents à la casserole, macros ±10 %, étapes détaillées.
- **FR-306**: Suppression du planning courant avec confirmation.
- **FR-307**: Migration légère V3 → V4 sans perte (modèles V1-V3 figés).
