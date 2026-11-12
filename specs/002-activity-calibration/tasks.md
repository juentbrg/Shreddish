# Tasks: Activité détaillée et calibration

**Input**: `specs/002-activity-calibration/` (spec.md, plan.md)
**Tests**: inclus, écrits avant le code (constitution V).

## Phase 1: Foundational

- [X] T101 Tests migration : store V1 avec profil → ouverture V2, profil intact, nouveaux champs nil, dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/MigrationTests.swift`
- [X] T102 `SchemaV1.Profile` figé, `SchemaV2`, étape lightweight, `ShreddishStore` sur V2 dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/SchemaV1.swift` + `SchemaV2.swift`
- [X] T103 Champs `Profile` : dailyActivityRaw?, trainingSessionsPerWeek?, trainingMinutes?, trainingIntensityRaw?, tdeeAdjustmentKcal?, lastCalibrationAt?, autoCalibrate? dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/Profile.swift`

## Phase 2: User Story 1 - Activité réelle (P1)

- [X] T104 [P] [US1] Tests `TrainingLoad` et dépense (référence 2529 / 2023 kcal, 0 séance, ancien niveau conservé, bornes « 0–14 séances, 15–240 min », ajustement inclus) dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/ActivityTests.swift`
- [X] T105 [US1] `DailyActivity`, `TrainingIntensity`, `TrainingLoad`, `ProfileInput` et `NutritionCalculator.tdee` étendus jusqu'à T104 vert
- [X] T106 [US1] Formulaire : activité quotidienne + entraînement (séances, durée, intensité, kcal estimées) dans `ios/App/Features/Onboarding/ProfileFormView.swift`
- [X] T107 [US1] Détail du calcul + invitation à préciser l'activité (ancien profil) dans `ios/App/Features/Targets/TargetsView.swift`
- [X] T108 [US1] UI test onboarding mis à jour (valeurs par défaut : bureau, 3 × 60 min modérées → 1819 kcal) dans `ios/UITests/OnboardingUITests.swift`

## Phase 3: User Story 2 - Calibration (P2)

- [X] T109 [P] [US2] Tests `EnergyCalibration` : jours complets, doublons de plannings, régression, 80 → 79 kg / 2000 kcal → 2550, données insuffisantes, rejet hors [60 %, 150 %], pas ½ plafonné ±150, total ±600 dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/EnergyCalibrationTests.swift`
- [X] T110 [US2] `EnergyCalibration` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Tracking/EnergyCalibration.swift` jusqu'à T109 vert
- [X] T111 [US2] `AppModel.calibrateIfDue` (7 jours, auto par défaut) + appel à l'ouverture et au retour au premier plan dans `ios/App/AppModel.swift`, `ios/App/RootView.swift`
- [X] T112 [US2] Section calibration (état des données, estimation, auto, recalibrer, réinitialiser) dans `ios/App/Features/Targets/CalibrationView.swift`

## Phase 4: Polish

- [X] T113 SwiftLint, tests Core / app / UI verts, installation iPhone
