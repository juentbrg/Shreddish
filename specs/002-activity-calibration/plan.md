# Implementation Plan: Activité détaillée et calibration

**Branch**: `002-activity-calibration` | **Date**: 2026-11-12 | **Spec**: [spec.md](./spec.md)

## Summary

Remplacer le niveau d'activité unique par activité quotidienne + charge d'entraînement (MET), et
ajouter une calibration hebdomadaire de la dépense par pesées + journal. Logique dans
`ShreddishCore` (TDD), migration SwiftData V1 → V2 légère.

## Technical Context

Stack inchangée (spec 001) : Swift 6, SwiftUI, SwiftData, Swift Testing. Aucune dépendance.

## Constitution Check

| Principe | Vérification | Statut |
|---|---|---|
| I | Usage perso, aucun backend | ✅ |
| II | Dépense et calibration par formules codées, IA non impliquée | ✅ |
| III | Données locales seulement | ✅ |
| IV | Champs ajoutés au `Profile`, pas de nouvelle entité | ✅ |
| V | Tests écrits avant : charge d'entraînement, calibration, migration | ✅ |

## Design

- `Model/Enums.swift` : `DailyActivity` (facteurs), `TrainingIntensity` (MET).
- `Nutrition/TrainingLoad.swift` : séances, durée, intensité, kcal par séance et par jour.
- `ProfileInput` : `dailyActivity?`, `training?`, `tdeeAdjustmentKcal`. Les deux premiers absents →
  ancien `ActivityLevel.factor` (FR-104).
- `CalculationBreakdown` : champs optionnels `dailyActivityFactor`, `exerciseKcalPerDay`,
  `calibrationKcal` (décodage des cibles déjà enregistrées dans les plannings).
- `Tracking/EnergyCalibration.swift` : `intakes(from:)`, `estimate(...)`, `nextAdjustment(...)`.
- `Model/SchemaV1.swift` : `SchemaV1.Profile` figé (copie exacte), `SchemaV2` avec `Profile`
  enrichi (champs optionnels), étape `.lightweight` V1 → V2.
- App : formulaire activité, section calibration dans Cibles, `AppModel.calibrateIfDue`
  à l'ouverture et au retour au premier plan.

## Complexity Tracking

| Choix | Pourquoi | Alternative écartée |
|---|---|---|
| Copie figée `SchemaV1.Profile` | Migration sans perte du store déjà installé (FR-111) | Modifier V1 : store existant illisible |
