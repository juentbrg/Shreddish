# Implementation Plan: Shreddish — planificateur de repas selon objectif

**Branch**: `001-shreddish-meal-planner` | **Date**: 2026-11-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-shreddish-meal-planner/spec.md`

## Summary

App iPhone perso : calculateur de cibles (Mifflin-St Jeor, objectif sèche / masse / recompo),
planning 7 jours généré par l'API OpenAI (sortie JSON stricte, validée localement),
ajustement repas / jour, journal alimentaire, liste de courses agrégée, suivi du poids.
SwiftUI + SwiftData, logique pure dans un package `ShreddishCore` testé en TDD, clé API en
Keychain, aucun backend.

## Technical Context

**Language/Version**: Swift 6 (toolchain 6.4, Xcode 27.2), strict concurrency

**Primary Dependencies**: SwiftUI, SwiftData, Observation, Swift Charts (courbe de poids),
Security (Keychain), URLSession.
Aucune dépendance tierce runtime. Outils de build : XcodeGen, SwiftLint (pré-build, comme Nowtick).

**Storage**: SwiftData local, schéma versionné (`SchemaV1` + `SchemaMigrationPlan` dès le départ), sans CloudKit ; clé API dans Keychain
(`WhenUnlockedThisDeviceOnly`)

**Testing**: Swift Testing (`swift test` sur `ShreddishCore`) ; XCUITest pour l'onboarding

**Target Platform**: iOS 26.0+, iPhone seulement, portrait

**Project Type**: mobile-app (iOS, sans backend)

**Performance Goals**: cibles recalculées < 100 ms ; semaine générée < 60 s (SC-003) ;
remplacement repas < 15 s (SC-007) ; UI 60 fps

**Constraints**: hors ligne sauf génération IA ; aucune donnée d'identité envoyée ; appels
IA seulement sur action explicite ; textes UI en français

**Scale/Scope**: 1 utilisateur ; ~52 plannings / an ; ~10 écrans

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principe | Vérification | Statut |
|---|---|---|
| I. Usage perso | Pas de compte, backend, partage, sync | ✅ |
| II. Calculs déterministes | `NutritionCalculator` codé, IA seulement pour repas ; `AIOutputValidator` avant affichage ; app utilisable sans IA | ✅ |
| III. Données locales / secrets | SwiftData local, Keychain `ThisDeviceOnly`, input IA limité (test dédié `PromptBuilder`) | ✅ |
| IV. Simplicité | Stack native, 0 dépendance runtime, un seul fournisseur IA, pas de couche repository générique | ✅ |
| V. Tests d'abord | Calculs, validation IA, agrégation, tendances : tests Swift Testing écrits avant code | ✅ |
| Contraintes | iOS seul, FR, disclaimer à l'onboarding, appels sur action | ✅ |

Re-check post-design (data-model, contracts) : ✅ aucune violation. Package local `ShreddishCore`
justifié ci-dessous (pas une violation, noté par transparence).

## Project Structure

### Documentation (this feature)

```text
specs/001-shreddish-meal-planner/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── ai-meal.schema.json
│   ├── ai-requests.md
│   └── core-api.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

Structure calquée sur Nowtick (`../nowtick/ios/`) : même outillage, même découpage app / Core.

```text
ios/
├── project.yml                  # XcodeGen (bundle app.shreddish, iOS 26, Swift 6 strict)
├── .swiftlint.yml               # règles reprises de Nowtick
├── Config/
│   ├── Debug.xcconfig           # #include? "Secrets.xcconfig"
│   └── Secrets.example.xcconfig # OPENAI_DEV_KEY vide ; Secrets.xcconfig git-ignoré
├── App/
│   ├── ShreddishApp.swift
│   ├── AppModel.swift           # @Observable central (profil, cibles, planning courant)
│   ├── Services/
│   │   ├── KeychainStore.swift
│   │   ├── OpenAIClient.swift   # Responses API via AITransport
│   │   ├── AITransport.swift    # protocole : URLSession (prod) / stub (UI tests)
│   │   ├── UITestAITransport.swift
│   │   ├── PlanGenerator.swift  # prompt → appel → validation → retry → save
│   │   └── ShoppingListSync.swift
│   ├── Features/
│   │   ├── Onboarding/  Targets/  Plan/  Journal/  Shopping/  Weight/  Settings/
│   └── Resources/               # Assets, Localizable.xcstrings (fr)
├── Packages/ShreddishCore/
│   ├── Package.swift            # iOS 26 + macOS 15 (swift test sans simulateur)
│   ├── Sources/ShreddishCore/
│   │   ├── Model/               # SchemaV1 (@Model), AppClock, LocalDay, enums
│   │   ├── Nutrition/           # NutritionCalculator, NutritionTargets
│   │   ├── AI/                  # DTO, schémas JSON, PromptBuilder, AIOutputValidator
│   │   ├── Tracking/            # Totals, WeeklySummary, WeightTrend
│   │   └── Shopping/            # ShoppingListBuilder
│   └── Tests/ShreddishCoreTests/   # + Fixtures/ (réponses IA JSON)
├── AppTests/                    # tests app (PlanGenerator avec transport stub, Keychain)
└── UITests/                     # parcours par user story, IA bouchonnée
```

**Structure Decision**: App iOS unique sous `ios/` + package local `ShreddishCore`, comme Nowtick.
Modèles SwiftData versionnés dans Core (comme `PlannerCore/Model/SchemaV1`) ; logique pure
testée en `swift test`. `AppClock` injectable : « aujourd'hui », J+6 et règle des 21 h testables.

## Phasage d'implémentation (pour /speckit-tasks)

1. Setup : `project.yml`, package Core, cible tests, `.gitignore`.
2. US1 (P1) : `NutritionCalculator` (TDD) → Onboarding + Targets + Profile SwiftData.
3. US2 (P2) : DTO + schémas + `PromptBuilder` + `AIOutputValidator` (TDD) → `KeychainStore`,
   `OpenAIClient`, `PlanGenerator` → Settings (clé, préférences) → vues Plan.
4. US3 (P3) : remplacement repas / régénération jour.
5. US4 (P4) : `Totals` + `WeeklySummary` (TDD) → Journal.
6. US5 (P5) : `ShoppingListBuilder` (TDD) → Shopping.
7. US6 (P6) : `WeightTrend` (TDD) → Weight + proposition recalcul.
8. Polish : états vides, erreurs IA, accessibilité Dynamic Type, icône.

## Complexity Tracking

| Choix | Pourquoi | Alternative plus simple écartée car |
|---|---|---|
| Package local `ShreddishCore` | Tests `swift test` sans simulateur, frontière nette logique / UI | Tout dans la cible app : tests lents, TDD pénible |
| DTO Core + `@Model` séparés | Logique pure testable sans container | `@Model` partout : logique couplée au store |
| Protocole `AITransport` | 2 usages concrets : URLSession prod + stub UI tests (pattern Nowtick `UITestSortTransport`) | Appels réseau réels en UI tests : lents, payants, non déterministes |
