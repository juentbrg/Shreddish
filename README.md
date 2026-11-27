# Shreddish

Shred + dish : app iPhone perso pour préparer une sèche (ou une prise de masse, une recomposition).
Cibles caloriques calculées par formule, planning de 7 jours généré par l'IA (repas simples, pas
chers, rapides), journal alimentaire, liste de courses, suivi du poids.

- iOS 26+, iPhone + app Apple Watch compagnon (watchOS 26+, WatchConnectivity), SwiftUI + SwiftData, aucune
  dépendance tierce.
- Spec 017 (version commercialisable) : foyer (plusieurs personnes), abonnement StoreKit 2, 5 langues (fr, en,
  es, de, it).
- Données sur l'appareil seulement : synchro iCloud (spec 017 FR-1701) non implémentée. Clé OpenAI fournie au
  build (spec 009).
- Spec Kit : constitution `.specify/memory/constitution.md`, feature `specs/001-shreddish-meal-planner/`.

## Structure

Monorepo : app iOS, app Android (à venir), backend, specs communes.

```text
ios/                          # app iPhone + Apple Watch (détail ci-dessous)
android/                      # app Android, à venir
backend/                      # API Rust (axum, SeaORM, Postgres)
specs/                        # specs Spec Kit, communes à toutes les plateformes
tools/                        # communs : pipelines de données (Ciqual, Open Prices), icône
```

```text
ios/
├── project.yml               # XcodeGen (Shreddish.xcodeproj non versionné)
├── App/                      # cible app : vues, services (OpenAI, Keychain, génération)
├── Watch/                    # cible Apple Watch (spec 017 FR-1711)
├── Shared/                   # code commun iPhone / Watch
├── Packages/ShreddishCore/      # logique pure + modèles SwiftData, testée en `swift test`
├── AppTests/                 # génération avec transport simulé
├── UITests/                  # parcours, IA simulée (`-uitest`)
├── Config/                   # App.xcconfig, Secrets.example.xcconfig
└── scripts/backup/           # sauvegarde / restauration des données de l'iPhone
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

## Backend

API Rust (axum, SeaORM, Postgres), pour le VPS. Spec 022 : installations anonymes, quota IA quotidien, abonnement
(essai = offre d'introduction Apple). Spec 023 : proxy OpenAI, une action consommée ouvre un ticket d'appels.
L'app iOS n'appelle pas encore le serveur et garde sa clé de build.

```bash
docker compose -f backend/compose.yaml up -d     # Postgres local, port 5433 (bases shreddish, shreddish_test)
cp backend/.env.example backend/.env
cd backend && cargo run                          # http://127.0.0.1:8080, migrations au démarrage
cargo test                                       # intégration sur vrai Postgres (TEST_DATABASE_URL)
```

Routes : `GET /health`, `POST /v1/installs`, `GET /v1/quota`, `POST /v1/quota/consume` (`{"kind": "week" |
"meal" | "day" | "recipe"}`, renvoie un ticket), `POST /v1/entitlements/verify` (dev : `{"proof":
"dev-subscription:7"}`), `POST /v1/ai/responses` (en-tête `X-Shreddish-Ticket`, corps Responses API : seuls
`input`, `text.format`, `stream` sont repris ; consignes système du serveur, `backend/prompts/` ; entrée limitée
aux clés que l'app envoie, `backend/prompts/input_keys.json`).
Prompts ou entrées modifiés dans l'app : `SHREDDISH_WRITE_PROMPTS=1 swift test --package-path
ios/Packages/ShreddishCore --filter PromptExport` recopie consignes, entrées types et clés admises dans
`backend/`. Nouvelle clé envoyée à l'IA : serveur déployé avant l'app, sinon requêtes refusées.
Réglages dans `.env` (`QUOTA_*`, `TICKET_*`, `OPENAI_*`) ; `ENTITLEMENT_VERIFIER=dev` refusé si
`APP_ENV=production`. Tests : OpenAI simulé, aucun appel facturé.

## Clé API OpenAI

- Copier `ios/Config/Secrets.example.xcconfig` en `ios/Config/Secrets.xcconfig` (git-ignoré) et
  remplir `OPENAI_API_KEY`. Clé copiée dans l'app au build ; aucune saisie dans l'app (spec 009).
- Usage perso seulement : une clé dans l'app est extractible. Ouverture à d'autres : serveur
  intermédiaire qui garde la clé.
- Génération réelle (facturée) : `TEST_RUNNER_SHREDDISH_LIVE=1 xcodebuild test ... -only-testing:AppTests/LiveGenerationTests`.
- Modèle : `gpt-6-luna`, fixe (spec 023).

## Macros et prix embarqués

- Macros : table Ciqual 2025 (ANSES, Licence Ouverte) :
  `python3 -I tools/ciqual/build_catalog.py "Table Ciqual 2025_FR.xlsx" ios/Packages/ShreddishCore/Sources/ShreddishCore/Resources/ciqual.json`.
- Prix : relevés Open Prices (Open Food Facts, ODbL), prix France médians, formats réels en rayon (mélangés : 1 kg + 500 g), sans magasin
  (spec 011). Export : `prices.parquet` du dépôt Hugging Face `openfoodfacts/open-prices`.

```bash
pip install duckdb
python3 tools/prices/build_prices.py prices.parquet \
  ios/Packages/ShreddishCore/Sources/ShreddishCore/Resources/ciqual.json \
  tools/prices/foods.json ios/Packages/ShreddishCore/Sources/ShreddishCore/Resources/prices.json
```

`tools/prices/foods.json` : un produit acheté par entrée. Correspondance aliments Ciqual ↔ catégories Open Prices,
libellé, rayon, formats vendus (`packs`), prix de repli (`price`), part comestible (`yield`), rapport cru / cuit
(`cooked`), périssabilité (`perishable`), unité (`unit`), poids à la pièce (`piece`).

## Installer sur l'iPhone

Ouvrir `ios/Shreddish.xcodeproj`, choisir son équipe dans Signing & Capabilities de la cible
Shreddish, sélectionner l'iPhone, Run.

Sans compte Apple Developer payant, la cible `ShreddishWatch` ne se signe pas en ligne de commande. La cible
`Shreddish` en dépend (`ios/project.yml`) : pour un build iPhone seul, retirer la dépendance
`- target: ShreddishWatch`, puis regénérer avec XcodeGen.

Sauvegarde / restauration des données de l'iPhone (devicectl, hors dépôt) : `ios/scripts/backup/backup.sh [dossier]`,
`ios/scripts/backup/restore.sh <dossier>` ; autre appareil : `DEVICE=<UDID>`.
