# Tasks: Shreddish — planificateur de repas selon objectif

**Input**: Design documents from `/specs/001-shreddish-meal-planner/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Inclus. Constitution V (NON-NEGOTIABLE) : tests de la logique `ShreddishCore` écrits
avant le code, et en échec avant implémentation.

**Organization**: Tâches groupées par user story, chaque story testable seule.

**Implémentation (2026-11-11)** : 65/66 ; T065 (scénarios manuels sur iPhone) reste à faire. Écarts : `PlanStore` (Core) remplace
`ShoppingListSync` (App) pour la persistance planning + courses, testé en `swift test` ; onglet
« Cibles » héberge cibles, profil et réglages ; icône provisoire via `ios/scripts/make-app-icon.swift`.

**Référence**: conventions reprises de Nowtick (`../nowtick/ios/`), cf. plan.md et research R9, R12–R14.

## Format: `[ID] [P?] [Story] Description`

- **[P]** : parallélisable (fichiers différents, aucune dépendance sur tâche non finie)
- **[Story]** : US1…US6 (spec.md)
- Chemins relatifs à la racine du repo

---

## Phase 1: Setup

**Purpose**: Squelette projet, package Core, build vert à vide.

- [X] T001 Créer `.gitignore` (`*.xcodeproj`, `.build/`, `DerivedData/`, `xcuserdata/`, `.DS_Store`, `ios/Config/Secrets.xcconfig`) à la racine
- [X] T002 Créer le package `ios/Packages/ShreddishCore/Package.swift` (swift-tools 6.0, plateformes iOS 26 / macOS 15, `swiftLanguageMode(.v6)`, cible `ShreddishCore`, cible test `ShreddishCoreTests` avec resources `.copy("Fixtures")`) — modèle : `../nowtick/ios/Packages/PlannerCore/Package.swift`
- [X] T003 Créer `ios/project.yml` XcodeGen sur le modèle de `../nowtick/ios/project.yml` : app `Shreddish` (iOS 26.0, iPhone, portrait, bundle `app.shreddish`, `SWIFT_STRICT_CONCURRENCY: complete`, String Catalogs), dépendance locale `ShreddishCore`, cibles `AppTests` et `UITests`, schemes `Shreddish` et `Shreddish-UITests`, pré-build SwiftLint, `configFiles: Debug: Config/Debug.xcconfig`, Info.plist `ShreddishOpenAIDevKey: $(OPENAI_DEV_KEY)`
- [X] T004 [P] Créer `ios/App/ShreddishApp.swift` (point d'entrée vide), `ios/App/Resources/Assets.xcassets`, `ios/.swiftlint.yml` (règles de `../nowtick/ios/.swiftlint.yml`), `ios/Config/Debug.xcconfig` (`#include? "Secrets.xcconfig"`) et `ios/Config/Secrets.example.xcconfig` (`OPENAI_DEV_KEY =`)
- [X] T005 [P] Créer `ios/App/Resources/Localizable.xcstrings` (langue de dev : fr)
- [X] T006 Vérifier `swift test --package-path ios/Packages/ShreddishCore`, `xcodegen generate --spec ios/project.yml && xcodebuild build` et SwiftLint verts

---

## Phase 2: Foundational

**Purpose**: Types partagés, horloge, schéma de persistance. Bloque toutes les stories.

- [X] T007 [P] Créer les enums Core `Sex`, `ActivityLevel` (facteurs 1.2 / 1.375 / 1.55 / 1.725 / 1.9), `Goal` (cut −20 %, bulk +10 %, recomp 0 %), `MealType`, `Aisle`, `Unit` (g, ml, piece), `MealStatus` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/Enums.swift` (Codable, Sendable, raw values snake_case conformes à `contracts/ai-meal.schema.json`)
- [X] T008 [P] Créer `AppClock` (injectable : now, calendrier, fuseau) et `LocalDay` (jour civil local, `+ n` jours) avec tests dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/AppClock.swift` + `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/LocalDayTests.swift` (modèle : `../nowtick/ios/Packages/PlannerCore/Sources/PlannerCore/Model/`) ; créer `MacroTotals` et `NutritionTargets` (bmr, tdee, targetKcal, proteinG, carbsG, fatG, floorApplied, warnings, breakdown) dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Nutrition/NutritionTargets.swift`
- [X] T009 Créer `SchemaV1: VersionedSchema` + `ShreddishMigrationPlan` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/SchemaV1.swift` (liste des @Model complétée au fil des stories) et `ios/App/ModelContainerFactory.swift` (container local, sans CloudKit ; variante in-memory pour previews/tests)
- [X] T010 Créer `ios/App/AppModel.swift` (@Observable central, `AppClock` injecté) et `ios/App/RootView.swift` : onboarding si pas de `Profile`, sinon `TabView` (Semaine, Journal, Courses, Poids, Réglages) avec onglets vides

**Checkpoint**: Fondations prêtes.

---

## Phase 3: User Story 1 - Calculer ses besoins selon l'objectif (P1) 🎯 MVP

**Goal**: Profil saisi → cibles kcal + macros + détail du calcul.

**Independent Test**: Profil homme 30 ans, 180 cm, 80 kg, modéré, sèche → 2207 kcal, P 160 / G 248 / L 64.

### Tests US1 (écrire d'abord, doivent échouer)

- [X] T011 [P] [US1] Tests `NutritionCalculator.validate` : bornes « âge 16–90, taille 120–230 cm, poids 35–250 kg », overrides « proteinPerKg 1,2–3,0 ; fatPerKg 0,6–1,5 ; calorieAdjustment −0,30 à +0,20 » dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/NutritionValidationTests.swift`
- [X] T012 [P] [US1] Tests BMR / TDEE / cibles avec valeurs de référence de `contracts/core-api.md` (homme → 1780 / 2759 / 2207, P160 L64 G248 ; femme → plancher 1345, `floorApplied = true`), protéines 1,8 g/kg en bulk, lipides réduits jusqu'à 0,6 g/kg (jamais moins) si glucides < 0 avec alerte, overrides appliqués, arrondis en fin de calcul, dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/NutritionCalculatorTests.swift`

### Implementation US1

- [X] T013 [US1] Implémenter `ProfileInput`, `ProfileValidationError`, `NutritionCalculator` (Mifflin-St Jeor, plancher max(1500 H / 1200 F, BMR en sèche), breakdown) dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Nutrition/NutritionCalculator.swift` jusqu'à T011–T012 verts
- [X] T014 [P] [US1] Créer `@Model Profile` (sex, birthDate, heightCm, weightKg, activity, goal, proteinPerKg?, fatPerKg?, calorieAdjustment?, disclaimerAcceptedAt?) + mapping `toProfileInput()` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/Profile.swift`, ajout à `SchemaV1`
- [X] T015 [US1] Créer `ios/App/Features/Onboarding/DisclaimerView.swift` (« outil personnel, pas un avis médical », acceptation obligatoire)
- [X] T016 [US1] Créer `ios/App/Features/Onboarding/ProfileFormView.swift` (formulaire réutilisable onboarding / édition, erreurs de bornes explicites)
- [X] T017 [US1] Créer `ios/App/Features/Targets/TargetsView.swift` : cible kcal, macros g + kcal, détail du calcul, avertissement plancher, recalcul immédiat à la modification (FR-002 à FR-005)
- [X] T018 [US1] Créer `ios/App/Features/Targets/MacroSettingsView.swift` : overrides protéines / lipides / ajustement calorique
- [X] T019 [US1] Brancher onboarding → Targets dans `ios/App/RootView.swift`
- [X] T020 [US1] Test UI parcours onboarding (disclaimer → profil → cibles affichées 2207 kcal) dans `ios/UITests/OnboardingUITests.swift`

**Checkpoint**: MVP utilisable : cibles de sèche connues.

---

## Phase 4: User Story 2 - Générer un planning de la semaine (P2)

**Goal**: Planning 7 jours (J à J+6) généré par IA, validé, persisté, consultable hors ligne.

**Independent Test**: Clé valide → 7 jours, 4 repas / jour, totaux ±10 %, persistant après relance.

### Tests US2 (écrire d'abord)

- [X] T021 [P] [US2] Tests décodage DTO depuis fixtures JSON (valide, champ manquant, enum inconnu, tronqué, `infeasible` non null → `AIError.infeasible(reason)` sans validation) dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/AIDecodingTests.swift` + fixtures `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/Fixtures/*.json`
- [X] T022 [P] [US2] Tests `AIOutputValidator` : 7 jours requis (day_offset 0–6), nb repas = mealsPerDay (collations incluses), « |kcal − (4P + 4G + 9L)| ≤ 10 % » sinon kcal recalculé, prepMinutes ≤ max, exclusion détectée (normalisée sans accents / casse) = fatal, jour > 10 % = warning, coût jour > 110 % du budget = warning, batch actif sans 1–2 sessions = fatal, `prep_session_ref` orphelin = fatal, batch inactif → refs remises à null, kg → g et l → ml dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/AIOutputValidatorTests.swift`
- [X] T023 [P] [US2] Tests `PromptBuilder` : input JSON conforme à `contracts/ai-requests.md`, aucune donnée hors FR-021 (pas d'âge, poids, sexe, taille) dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/PromptBuilderTests.swift`
- [X] T024 [P] [US2] Tests `Totals.planned` et `Totals.deviation` dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/TotalsTests.swift`

### Implementation US2

- [X] T025 [P] [US2] Créer DTO `WeekPlanDTO`, `DayPlanDTO`, `MealDTO`, `IngredientDTO`, `PrepSessionDTO` (CodingKeys snake_case) dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/AI/DTOs.swift`
- [X] T026 [P] [US2] Embarquer les 3 schémas de `contracts/ai-meal.schema.json` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/AI/ResponseSchemas.swift`
- [X] T027 [US2] Implémenter `AIOutputValidator` + `ValidationResult` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/AI/AIOutputValidator.swift` jusqu'à T022 vert
- [X] T028 [US2] Implémenter `PromptBuilder` (instructions système + inputs week) dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/AI/PromptBuilder.swift` jusqu'à T023 vert
- [X] T029 [US2] Implémenter `Totals.planned` / `deviation` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Tracking/Totals.swift` jusqu'à T024 vert
- [X] T030 [P] [US2] Créer `@Model Preferences` (mealsPerDay 2–5 défaut 4, collations incluses, maxPrepMinutes 5–90 défaut 20, dailyBudgetEUR 3–40 défaut 8, excludedFoods, likedFoods, equipment, batchCooking défaut false, aiModel) dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/Preferences.swift`, ajout à `SchemaV1`
- [X] T031 [P] [US2] Créer `@Model WeeklyPlan` (startDate = jour de génération, jours J à J+6 via `LocalDay`, targetsSnapshot, prepSessions, days exactement 7 cascade, isCurrent unique), `DayPlan`, `Meal` (status défaut planned) + mapping DTO dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/PlanModels.swift`, ajout à `SchemaV1`
- [X] T032 [P] [US2] Implémenter `KeychainStore` (generic password, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, save / read / delete ; en Debug seulement, si vide, amorçage depuis Info.plist `ShreddishOpenAIDevKey` — research R13) dans `ios/App/Services/KeychainStore.swift`
- [X] T033 [US2] Implémenter `OpenAIClient` (Responses API, json_schema strict, timeout 90 s, mapping `AIError` selon tableau d'erreurs de `contracts/ai-requests.md`, test de clé via `GET /v1/models`, clé jamais loggée) + `AIConfig.defaultModel` dans `ios/App/Services/OpenAIClient.swift`, via protocole `ios/App/Services/AITransport.swift` (URLSession) et stub `ios/App/Services/UITestAITransport.swift` activé par argument de lancement UI tests (fixtures JSON) — modèle : `../nowtick/ios/App/Services/UITestSortTransport.swift`
- [X] T034 [US2] Implémenter `PlanGenerator.generateWeek` (déclenché seulement par action utilisateur, jamais en tâche de fond — FR-020 ; prompt → appel → validation → 1 retry → repli 7 requêtes jour sur timeout → sauvegarde atomique, ancien planning `isCurrent = false`) dans `ios/App/Services/PlanGenerator.swift` + tests avec transport stub dans `ios/AppTests/PlanGeneratorTests.swift`
- [X] T035 [US2] Créer `ios/App/Features/Settings/APIKeyView.swift` (saisie masquée, tester, remplacer, supprimer — FR-019)
- [X] T036 [US2] Créer `ios/App/Features/Settings/PreferencesView.swift` (FR-007, FR-008, toggle batch cooking, modèle IA)
- [X] T037 [US2] Créer `ios/App/Features/Plan/WeekView.swift` (7 jours, bouton générer, état chargement, invitation clé si absente, erreurs `AIError` lisibles)
- [X] T038 [US2] Créer `ios/App/Features/Plan/DayView.swift` (repas, total vs cible, badge hors cible > 10 %, badge hors budget > 110 %) et `ios/App/Features/Plan/MealDetailView.swift` (ingrédients, étapes, temps, coût, macros)
- [X] T039 [US2] Créer `ios/App/Features/Plan/PrepSessionView.swift` (sessions batch cooking si présentes)
- [X] T040 [US2] Créer `ios/App/Features/Plan/PlanHistoryView.swift` (plannings précédents consultables — FR-013)

**Checkpoint**: Semaine générée et consultable hors ligne.

---

## Phase 5: User Story 3 - Ajuster le planning (P3)

**Goal**: Remplacer un repas ou régénérer un jour sans toucher au reste.

**Independent Test**: Remplacer déjeuner mercredi → seul ce repas change, total jour ±10 %.

- [X] T041 [P] [US3] Tests `PromptBuilder.dayInput` / `replaceMealInput` (remaining_targets = cible − autres repas, avoid_meal_names) dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/PromptBuilderTests.swift`
- [X] T042 [US3] Implémenter `dayInput` / `replaceMealInput` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/AI/PromptBuilder.swift`
- [X] T043 [US3] Ajouter `PlanGenerator.regenerateDay` / `replaceMeal` (nouveau Meal, statut `planned`, autres jours intacts) dans `ios/App/Services/PlanGenerator.swift`
- [X] T044 [US3] Ajouter actions « Remplacer » (repas) et « Régénérer la journée » dans `ios/App/Features/Plan/DayView.swift` et `ios/App/Features/Plan/MealDetailView.swift`

**Checkpoint**: Planning ajustable.

---

## Phase 6: User Story 4 - Journal alimentaire (P4)

**Goal**: Repas mangés / sautés, extras, bilan réel jour et semaine.

**Independent Test**: 2 repas mangés, 1 sauté, 1 extra 300 kcal → bilan réel exact.

- [X] T045 [P] [US4] Tests `Totals.actual` (seuls `eaten` + extras comptés) et `Totals.weeklySummary` (moyennes, adhérence = eaten / repas des jours écoulés, jour courant inclus seulement après 21 h, via `AppClock`) dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/TrackingTests.swift`
- [X] T046 [US4] Implémenter `Totals.actual`, `WeeklySummary`, `ExtraDTO`, `DayLogDTO` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Tracking/`
- [X] T047 [P] [US4] Créer `@Model ExtraEntry` (name, quantityLabel?, kcal / proteinG / carbsG / fatG ≥ 0, loggedAt) lié à `DayPlan` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/ExtraEntry.swift`, ajout à `SchemaV1`
- [X] T048 [US4] Créer `ios/App/Features/Journal/JournalDayView.swift` (statut par repas mangé / sauté, réel vs prévu vs cible)
- [X] T049 [US4] Créer `ios/App/Features/Journal/AddExtraView.swift` (FR-018)
- [X] T050 [US4] Créer `ios/App/Features/Journal/WeeklySummaryView.swift` (FR-018b)

**Checkpoint**: Adhérence suivie.

---

## Phase 7: User Story 5 - Liste de courses (P5)

**Goal**: Liste agrégée par rayon, quantités cumulées, coût, coches persistantes.

**Independent Test**: Planning fixture → quantités cumulées correctes, coches gardées après régénération.

- [X] T051 [P] [US5] Tests `ShoppingListBuilder` : normalisation (minuscules, sans accents, trim, espaces réduits, « ux » → « u », « s » final retiré sauf « ss », mots > 3 lettres), fusion par (nom normalisé, unité), unités différentes = lignes séparées, tri rayon puis nom, coût total dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/ShoppingListBuilderTests.swift`
- [X] T052 [US5] Implémenter `ShoppingListBuilder` + `ShoppingLine` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Shopping/ShoppingListBuilder.swift`
- [X] T053 [P] [US5] Créer `@Model ShoppingItem` (plan, name, key, totalQuantity, unit, aisle, costEUR, isChecked) dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/ShoppingItem.swift`, ajout à `SchemaV1`
- [X] T054 [US5] Créer `ios/App/Services/ShoppingListSync.swift` : reconstruction après génération / remplacement, `isChecked` conservé par `key`
- [X] T055 [US5] Créer `ios/App/Features/Shopping/ShoppingListView.swift` (sections par rayon, cases à cocher, coût total)

**Checkpoint**: Courses prêtes depuis le planning.

---

## Phase 8: User Story 6 - Suivi du poids (P6)

**Goal**: Pesées, courbe, alerte rythme, recalcul des cibles.

**Independent Test**: 82 → 80 kg en 2 semaines en sèche → alerte + proposition de recalcul.

- [X] T056 [P] [US6] Tests `WeightTrend` (taux % / semaine, nil si < 2 semaines, alerte > 1 % seulement en sèche) dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/WeightTrendTests.swift`
- [X] T057 [US6] Implémenter `WeightTrend` dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Tracking/WeightTrend.swift`
- [X] T058 [P] [US6] Créer `@Model WeightEntry` (date unique par jour via `LocalDay`, weightKg 35–250) dans `ios/Packages/ShreddishCore/Sources/ShreddishCore/Model/WeightEntry.swift`, ajout à `SchemaV1`
- [X] T059 [US6] Créer `ios/App/Features/Weight/WeightView.swift` (saisie, courbe Swift Charts, alerte rythme)
- [X] T060 [US6] Après pesée : proposition « Recalculer mes cibles » → maj `Profile.weightKg` → cibles recalculées (FR-017) dans `ios/App/Features/Weight/WeightView.swift`

**Checkpoint**: Toutes les stories fonctionnelles.

---

## Phase 9: Polish & Cross-Cutting

- [X] T061 [P] États vides (pas de planning, pas de pesée, liste vide) dans les vues concernées de `ios/App/Features/`
- [X] T062 [P] Accessibilité : Dynamic Type, labels VoiceOver sur macros et boutons IA, dans `ios/App/Features/`
- [X] T063 [P] Icône app dans `ios/App/Resources/Assets.xcassets/AppIcon.appiconset`
- [X] T064 Audit logs : aucune clé ni header `Authorization` loggé (grep `ios/App/Services/`)
- [ ] T065 Dérouler les 13 scénarios (chronos SC-001, SC-003, SC-007 notés) de `specs/001-shreddish-meal-planner/quickstart.md` sur simulateur puis iPhone
- [X] T066 Créer `README.md` (build, tests, XcodeGen, `Secrets.xcconfig`, saisie clé API)

---

## Dependencies & Execution Order

### Phases

- Setup (1) → Foundational (2) → stories.
- US1 : aucune dépendance de story. MVP.
- US2 : dépend de US1 (cibles nécessaires à la génération).
- US3, US4, US5 : dépendent de US2 (planning) ; indépendantes entre elles, parallélisables.
- US6 : dépend de US1 seulement ; parallélisable avec US2–US5.
- Polish : après les stories voulues.

### Dans chaque story

Tests Core (rouges) → implémentation Core (verts) → `@Model` (+ `SchemaV1`) → services → vues.

### Parallel Opportunities

- Phase 2 : T007, T008 en parallèle.
- US1 : T011 + T012 ensemble ; puis T014 en parallèle de T013.
- US2 : T021–T024 ensemble ; T025, T026, T030, T031, T032 ensemble.
- Après US2 : US3, US4, US5 en parallèle ; US6 dès US1 terminée.

## Parallel Example: User Story 2

```bash
# Tests d'abord, en parallèle :
T021 AIDecodingTests.swift
T022 AIOutputValidatorTests.swift
T023 PromptBuilderTests.swift
T024 TotalsTests.swift

# Puis modèles et infra, en parallèle :
T025 DTOs.swift   T026 ResponseSchemas.swift   T030 Preferences.swift
T031 PlanModels.swift   T032 KeychainStore.swift
```

## Implementation Strategy

### MVP First

1. Phases 1–2.
2. Phase 3 (US1) → cibles de sèche utilisables sur iPhone.
3. **STOP & VALIDATE** : vérifier valeurs de référence, installer sur iPhone.

### Incremental Delivery

1. US1 → cibles.
2. US2 → planning IA (valeur principale).
3. US3 + US4 → planning suivable au quotidien.
4. US5 → courses.
5. US6 → réajustement au fil de la sèche.
