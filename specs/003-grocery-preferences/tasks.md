# Tasks: Préférences de courses

**Tests**: inclus, écrits avant le code (constitution V).

- [X] T201 Tests validation : budget semaine (rejet / signalé / ok), allergène, plafond jour et repas, dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/BudgetValidationTests.swift`
- [X] T202 Tests `BudgetMath` (plafond jour, plafond repas) dans le même fichier
- [X] T203 Tests `PromptBuilder` : nouvelles clés, consignes magasin / disponibilité / allergies, dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/PromptBuilderTests.swift`
- [X] T204 Test migration V2 → V3 (préférences conservées, budget hebdo = jour × 7) dans `ios/Packages/ShreddishCore/Tests/ShreddishCoreTests/MigrationTests.swift`
- [X] T205 Enums, `Preferences`, `SchemaV1.Preferences` figé, `SchemaV3`, plan de migration
- [X] T206 `GenerationConstraints`, `AIOutputValidator`, `BudgetMath`, `PromptBuilder` jusqu'aux tests verts
- [X] T207 `PlanGenerator` : plafonds jour / repas, contraintes, transport UI test
- [X] T208 Écran Préférences : budget, tolérance, magasin, disponibilité, allergies, n'aime pas
- [X] T209 Liste de courses et semaine : total vs budget et tolérance
- [X] T210 SwiftLint, tests Core / app / UI, installation iPhone
