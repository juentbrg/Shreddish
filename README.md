# Shreddish

Shred + dish : app iPhone perso pour préparer une sèche (ou une prise de masse, une recomposition).
Cibles caloriques calculées par formule, planning de 7 jours généré par l'IA (repas simples, pas
chers, rapides), journal alimentaire, liste de courses, suivi du poids.

- iOS 26+, iPhone, SwiftUI + SwiftData, aucune dépendance tierce.
- Données sur l'appareil seulement ; clé OpenAI fournie au build (spec 009).
- Spec Kit : constitution `.specify/memory/constitution.md`, feature `specs/001-shreddish-meal-planner/`.

## Structure

```text
ios/
├── project.yml               # XcodeGen (Shreddish.xcodeproj non versionné)
├── App/                      # cible app : vues, services (OpenAI, Keychain, génération)
├── Packages/ShreddishCore/      # logique pure + modèles SwiftData, testée en `swift test`
├── AppTests/                 # génération avec transport simulé
├── UITests/                  # parcours, IA simulée (`-uitest`)
├── Config/                   # App.xcconfig, Secrets.example.xcconfig
└── scripts/make-app-icon.swift
```

## Build et tests

```bash
# Logique métier, sans simulateur
swift test --package-path ios/Packages/ShreddishCore

# Projet Xcode. Lancer le binaire réel : via le lien de ~/.local/bin, XcodeGen ne trouve pas
# ses presets (PRODUCT_NAME vide sur les cibles de test, pas de flag DEBUG).
~/.local/opt/xcodegen/bin/xcodegen generate --spec ios/project.yml

xcodebuild test -project ios/Shreddish.xcodeproj -scheme Shreddish \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project ios/Shreddish.xcodeproj -scheme Shreddish-UITests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

SwiftLint tourne en pré-build (`ios/.swiftlint.yml`).

## Clé API OpenAI

- Copier `ios/Config/Secrets.example.xcconfig` en `ios/Config/Secrets.xcconfig` (git-ignoré) et
  remplir `OPENAI_API_KEY`. Clé copiée dans l'app au build ; aucune saisie dans l'app (spec 009).
- Usage perso seulement : une clé dans l'app est extractible. Ouverture à d'autres : serveur
  intermédiaire qui garde la clé.
- Génération réelle (facturée) : `TEST_RUNNER_SHREDDISH_LIVE=1 xcodebuild test ... -only-testing:AppTests/LiveGenerationTests`.
- Modèle par défaut : `gpt-6-luna`, modifiable dans Réglages → Préférences repas.

## Macros et prix embarqués

- Macros : table Ciqual 2025 (ANSES, Licence Ouverte), `python3 tools/ciqual/build_catalog.py`.
- Prix : relevés Open Prices (Open Food Facts, ODbL), prix France au quartile bas, sans magasin
  (spec 011). Export : `prices.parquet` du dépôt Hugging Face `openfoodfacts/open-prices`.

```bash
pip install duckdb
python3 tools/prices/build_prices.py prices.parquet \
  ios/Packages/ShreddishCore/Sources/ShreddishCore/Resources/ciqual.json \
  tools/prices/foods.json ios/Packages/ShreddishCore/Sources/ShreddishCore/Resources/prices.json
```

Correspondance aliments Ciqual ↔ catégories Open Prices : `tools/prices/foods.json`.

## Installer sur l'iPhone

Ouvrir `ios/Shreddish.xcodeproj`, choisir son équipe dans Signing & Capabilities de la cible
Shreddish, sélectionner l'iPhone, Run.
