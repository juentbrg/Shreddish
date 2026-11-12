# Data Model: Shreddish

Deux couches :
- **ShreddishCore** (package Swift) : types valeur `struct`/`enum`, `Codable`, `Sendable`, sans
  persistance. Toute la logique (calculs, validation, agrégation) opère dessus.
- **Persistance** (SwiftData, `ShreddishCore/Model`, `SchemaV1: VersionedSchema` + plan de
  migration, pattern Nowtick) : `@Model` persistés, conversion vers/depuis les types valeur.

## Enums (Core)

- `Sex` : `male`, `female`
- `ActivityLevel` : `sedentary` (1.2), `light` (1.375), `moderate` (1.55), `active` (1.725),
  `veryActive` (1.9)
- `Goal` : `cut` (−20 %), `bulk` (+10 %), `recomp` (0 %)
- `MealType` : `breakfast`, `lunch`, `dinner`, `snack`
- `Aisle` : `fruitsLegumes`, `viandePoisson`, `cremerie`, `epicerie`, `surgeles`,
  `boulangerie`, `autre`
- `Unit` : `g`, `ml`, `piece`
- `MealStatus` : `planned`, `eaten`, `skipped`

## Profile (@Model, singleton)

| Champ | Type | Règle |
|---|---|---|
| sex | Sex | requis |
| birthDate | Date | âge calculé 16–90 ans |
| heightCm | Double | 120–230 |
| weightKg | Double | 35–250 ; mis à jour par dernière pesée acceptée |
| activity | ActivityLevel | requis |
| goal | Goal | requis |
| proteinPerKg | Double? | override ; défaut selon goal ; 1,2–3,0 |
| fatPerKg | Double? | override ; défaut 0,8 ; 0,6–1,5 |
| calorieAdjustment | Double? | override ; −0,30 à +0,20 |
| disclaimerAcceptedAt | Date? | requis avant usage |

Âge stocké via date de naissance : pas de profil périmé.

## NutritionTargets (Core, dérivé, non persisté sauf snapshot)

`bmr`, `tdee`, `targetKcal`, `proteinG`, `carbsG`, `fatG`, `floorApplied: Bool`,
`warnings: [TargetWarning]`, `breakdown` (étapes de calcul affichables, FR-005).

## Preferences (@Model, singleton)

| Champ | Type | Défaut | Règle |
|---|---|---|---|
| mealsPerDay | Int | 4 | 2–5, collations incluses |
| maxPrepMinutes | Int | 20 | 5–90 |
| dailyBudgetEUR | Double | 8 | 3–40 |
| excludedFoods | [String] | [] | allergies + dégoûts |
| likedFoods | [String] | [] | |
| equipment | [String] | [] | ex. micro-ondes, airfryer |
| batchCooking | Bool | false | FR-014 |
| aiModel | String | AIConfig.defaultModel | |

## WeeklyPlan (@Model)

| Champ | Type | Règle |
|---|---|---|
| id | UUID | |
| startDate | Date | jour de génération (début de journée) ; fin = startDate + 6 j |
| createdAt | Date | |
| targetsSnapshot | NutritionTargets (Codable) | cibles au moment de la génération |
| prepSessions | [PrepSession] | vide si batch off |
| days | [DayPlan] | exactement 7, cascade delete |
| isCurrent | Bool | un seul `true` |

Un nouveau planning n'écrase pas l'ancien (FR-013) : l'ancien passe `isCurrent = false`.
Écriture seulement après validation complète (edge case « génération interrompue »).

## DayPlan (@Model)

`date`, `meals: [Meal]` (cascade), `extras: [ExtraEntry]` (cascade).
Dérivés (calculés, non stockés) : `plannedTotals`, `plannedCostEUR`, `actualTotals`
(meals `eaten` + extras), `deviation` vs cible, `isOffTarget` (> 10 %), `isOverBudget`
(> 110 % du budget).

## Meal (@Model)

| Champ | Type | Règle |
|---|---|---|
| type | MealType | |
| name | String | non vide |
| ingredients | [Ingredient] (Codable) | ≥ 1 |
| steps | [String] | ≥ 1 |
| prepMinutes | Int | ≤ maxPrepMinutes |
| costEUR | Double | ≥ 0 |
| kcal, proteinG, carbsG, fatG | Double | ≥ 0 ; cohérence ±10 % |
| prepSessionRef | Int? | index session batch |
| status | MealStatus | défaut `planned` |
| statusChangedAt | Date? | |

Transitions `status` : `planned ↔ eaten`, `planned ↔ skipped`, `eaten ↔ skipped`. Remplacement
d'un repas : nouveau Meal, statut remis à `planned`.

## Ingredient (Core, Codable, embarqué)

`name`, `quantity: Double` (> 0), `unit: Unit`, `aisle: Aisle`, `costEUR: Double`.

## PrepSession (Core, Codable, embarqué)

`index`, `dayOffset` (0–6), `title`, `durationMinutes`, `steps: [String]`.

## ExtraEntry (@Model)

`name`, `quantityLabel: String?`, `kcal`, `proteinG`, `carbsG`, `fatG` (≥ 0), `loggedAt`.

## ShoppingItem (@Model)

| Champ | Type |
|---|---|
| plan | WeeklyPlan (relation) |
| name | String (nom affiché) |
| key | String (nom normalisé + unité) |
| totalQuantity | Double |
| unit | Unit |
| aisle | Aisle |
| costEUR | Double |
| isChecked | Bool |

Liste regénérée à chaque modif du planning ; état `isChecked` conservé par `key`.

## WeightEntry (@Model)

`date` (unique par jour), `weightKg` (35–250).
Règle alerte sèche : perte moyenne > 1 % du poids / semaine sur les 2 dernières semaines.

## WeeklySummary (Core, dérivé)

`avgActualKcal`, `avgProteinG`, `avgCarbsG`, `avgFatG`, `adherenceRate` =
repas `eaten` / repas des jours écoulés du planning (jour courant inclus seulement après
21 h, sinon exclu).

## Relations

```text
Profile 1 ─ 1 Preferences
WeeklyPlan 1 ─ 7 DayPlan 1 ─ n Meal
                      DayPlan 1 ─ n ExtraEntry
WeeklyPlan 1 ─ n ShoppingItem
WeightEntry (indépendant)
```
