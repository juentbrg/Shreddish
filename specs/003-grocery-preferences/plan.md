# Implementation Plan: Préférences de courses

**Branch**: `003-grocery-preferences` | **Date**: 2026-11-12 | **Spec**: [spec.md](./spec.md)

## Summary

`Preferences` enrichies (budget hebdo, tolérance, allergies, disponibilité, magasin), contrôle budget
semaine / jour / repas dans `AIOutputValidator`, consignes IA dans `PromptBuilder`, SchemaV3.

## Constitution Check

| Principe | Vérification | Statut |
|---|---|---|
| I | Pas de backend ni d'API de prix : estimations IA, dites comme telles | ✅ |
| II | Budget et exclusions vérifiés localement, IA en suggestion | ✅ |
| III | Magasin et préférences envoyés à l'IA : préférences repas, aucune identité | ✅ |
| IV | Champs ajoutés à `Preferences`, enums simples | ✅ |
| V | Tests avant : budget, allergies, prompt, migration | ✅ |

## Design

- `Model/Enums` : `IngredientAvailability`, `GroceryStore` (raw values snake_case).
- `Preferences` : `weeklyBudgetEUR?`, `budgetTolerance?`, `allergies?`, `ingredientAvailabilityRaw?`,
  `storeRaw?`, `customStoreName?` (optionnels → migration légère) + accesseurs avec défauts.
- `SchemaV1.Preferences` figé (forme V1 = V2) ; `SchemaV2` le référence ; `SchemaV3` = modèles courants.
- `GenerationConstraints` : `weeklyBudgetEur`, `budgetTolerance`, `allergies`, `costLimitEur?`
  (jour ou repas). Validation : `weekOverBudget` (fatal) / `weekOverBudgetWithinTolerance`
  (avertissement), `allergen` (fatal), `overCostLimit` (fatal).
- `BudgetMath` : plafonds jour et repas (FR-203).
- `PromptPreferences` : `weekly_budget_eur`, `budget_tolerance`, `allergies`, `disliked_foods`,
  `ingredient_availability`, `store`, `cost_limit_eur`.
- App : écran Préférences réorganisé, total courses vs budget, avertissement semaine.
