# Quickstart : validation Shreddish

## Prérequis

- Xcode 27+ (Swift 6), simulateur iOS 26+ ou iPhone perso.
- XcodeGen (`xcodegen --version`).
- Clé API OpenAI (seulement pour scénarios IA).

## Build et tests

```bash
# Logique métier (rapide, sans simulateur)
swift test --package-path ios/Packages/ShreddishCore

# Génération projet + tests app
~/.local/opt/xcodegen/bin/xcodegen generate --spec ios/project.yml  # binaire réel, cf. README
xcodebuild test -project ios/Shreddish.xcodeproj -scheme Shreddish \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Attendu : tous les tests verts, dont valeurs de référence de
[core-api.md](./contracts/core-api.md#nutrition).

## Scénarios manuels

1. **Onboarding (US1, SC-001 < 2 min, chronométré)** : installation neuve → disclaimer → profil homme 30 ans, 180 cm, 80 kg,
   modéré, sèche → cible 2207 kcal, P 160 / G 248 / L 64, détail du calcul visible.
2. **Bornes (US1)** : taille 30 cm → refus, message explicite.
3. **Sans clé (US2)** : « Générer la semaine » sans clé → invitation réglages ; onglet
   cibles toujours utilisable.
4. **Clé** : saisie clé → « Tester » → valide ; clé masquée ensuite.
5. **Planning (US2, SC-003 chronométré)** : générer un mercredi → 7 jours du mercredi au
   mardi suivant en < 60 s, 4 repas / jour, totaux jour ±10 %, jours
   hors cible signalés. Kill app + relance → planning présent, aucun appel réseau.
6. **Ajustement (US3, SC-007 < 15 s chronométré)** : remplacer le déjeuner du mercredi → seul
   ce repas change.
   Régénérer jeudi → seul jeudi change.
7. **Journal (US4)** : lundi, déjeuner « mangé », dîner « sauté », extra 300 kcal → bilan
   réel = kcal du déjeuner + 300 (repas `planned` et `skipped` non comptés).
8. **Courses (US5)** : liste groupée par rayon, ingrédients fusionnés, cocher → état gardé
   après relance. Remplacement d'un repas → liste mise à jour, coches conservées.
9. **Poids (US6)** : 3 pesées sur 2 semaines, 82 → 80 kg → alerte rythme trop rapide,
   proposition de recalcul.
10. **Hors ligne** : mode avion → génération = message `offline`, reste de l'app OK.
11. **Exclusions** : exclure « thon » → aucun repas généré ne contient thon.
12. **Budget (SC-006)** : budget 4 € / jour → jours au-delà de 4,40 € signalés.
13. **Batch cooking** : option active → 1 à 2 sessions de préparation affichées, repas liés.
