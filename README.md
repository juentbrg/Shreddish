# Shreddish

Shred + dish : app iPhone perso pour préparer une sèche (ou une prise de masse, une recomposition).
Cibles caloriques calculées par formule, planning de 7 jours généré par l'IA (repas simples, pas
chers, rapides), journal alimentaire, liste de courses, suivi du poids.

- iOS 26+, iPhone, SwiftUI + SwiftData, aucune dépendance tierce.
- Données sur l'appareil seulement ; clé OpenAI dans le trousseau iOS.
- Spec Kit : constitution `.specify/memory/constitution.md`, feature `specs/001-shreddish-meal-planner/`.

## Structure

```text
ios/
├── project.yml               # XcodeGen (Shreddish.xcodeproj non versionné)
├── App/                      # cible app : vues, services (OpenAI, Keychain, génération)
├── Packages/ShreddishCore/      # logique pure + modèles SwiftData, testée en `swift test`
├── AppTests/                 # génération avec transport simulé
├── UITests/                  # parcours, IA simulée (`-uitest`)
├── Config/                   # Debug.xcconfig, Secrets.example.xcconfig
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

- Dans l'app : Cibles → Réglages → Clé API OpenAI (saisir, tester, supprimer).
- En développement : copier `ios/Config/Secrets.example.xcconfig` en `ios/Config/Secrets.xcconfig`
  (git-ignoré) et remplir `OPENAI_DEV_KEY`. Les builds Debug la copient dans le trousseau au
  premier lancement si celui-ci est vide. Les builds Release ne la lisent jamais.
- Modèle par défaut : `gpt-6-luna`, modifiable dans Réglages → Préférences repas.

## Installer sur l'iPhone

Ouvrir `ios/Shreddish.xcodeproj`, choisir son équipe dans Signing & Capabilities de la cible
Shreddish, sélectionner l'iPhone, Run.
