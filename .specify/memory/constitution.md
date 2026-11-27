<!--
Sync Impact Report
- Version : 1.0.0 → 2.0.0 (MAJOR : principe I redéfini pour la spec 017, commercialisation)
- Principes modifiés :
  - I. Usage personnel d'abord → I. Personnel d'abord, ouvrable à d'autres
  - III. Données locales et secrets protégés : iCloud prévu (FR-1701), clé embarquée bornée à
    l'usage perso
- Sections modifiées : Contraintes techniques (iPhone + Apple Watch, 5 langues, mention médicale,
  appels IA automatiques bornés, compte Apple gratuit) ; Workflow (specs a posteriori)
- Sections ajoutées : aucune
- Sections retirées : aucune
- TODO différés : aucun
-->

# Shreddish Constitution

## Core Principles

### I. Personnel d'abord, ouvrable à d'autres

Shreddish (shred + dish) sert d'abord son auteur, sur son iPhone. Il peut être ouvert à
d'autres via l'App Store (spec 017 : foyer, régimes, abonnement).
- Aucun compte utilisateur ni backend propre tant qu'une exigence ne l'impose pas
  (ex. serveur de clé IA, principe III).
- Chaque fonctionnalité MUST servir directement l'objectif : manger simple, pas cher, rapide,
  aligné sur l'objectif physique (sèche, prise de masse, recomposition).
- Aucune fonctionnalité sociale. Le foyer (plusieurs personnes, un appareil) est permis.
- Une fonctionnalité sans usage hebdomadaire réel attendu est refusée.

### II. Calculs déterministes, IA en suggestion

- Besoins caloriques et macros MUST provenir de formules reconnues, codées et vérifiables
  (ex. Mifflin-St Jeor + facteur d'activité). Jamais calculés par l'IA.
- Macros des aliments et prix : tables embarquées (Ciqual, Open Prices), jamais l'IA.
- L'IA génère seulement des idées de repas et de plannings. Ses sorties MUST être validées
  (format, valeurs nutritionnelles plausibles, écart aux cibles) avant affichage.
- Panne ou absence d'IA : calculateur et planning existant restent utilisables.

### III. Données locales et secrets protégés

- Profil, plannings, historique : stockés sur l'appareil. Synchronisation iCloud privée prévue
  (spec 017, FR-1701), pas encore implémentée. Jamais d'autre stockage distant.
- Clé API OpenAI MUST venir de `ios/Config/Secrets.xcconfig` (git-ignoré), copiée dans l'app au
  build (spec 009). Jamais dans le code, le repo, les logs ni un fichier de config versionné.
- Clé embarquée tolérée en usage perso seulement. Avant toute distribution publique : clé sur un
  serveur intermédiaire, jamais dans l'app.
- Seules données envoyées à l'IA : celles nécessaires à la génération (cibles, préférences,
  contraintes), après consentement. Aucune donnée d'identité.

### IV. Simplicité (YAGNI)

- Stack Apple native, dépendances tierces seulement si justifiées dans le plan.
- Pas d'abstraction spéculative : un seul fournisseur IA tant qu'un second n'est pas demandé.
- Toute complexité ajoutée MUST être justifiée dans la section « Complexity Tracking » du plan.

### V. Calculs testés d'abord (NON-NEGOTIABLE)

- Calculs nutritionnels (BMR, TDEE, ajustement objectif, répartition macros, totaux de
  planning) et calculs de prix et de courses : tests unitaires écrits avant l'implémentation,
  avec valeurs de référence connues.
- Parsing et validation des réponses IA : testés sur réponses valides, invalides et tronquées.

## Contraintes techniques

- Plateformes : iPhone (iOS 26+) et app compagnon Apple Watch.
- Langues : français (référence), anglais, espagnol, allemand, italien. Noms d'ingrédients en
  français (tables Ciqual et prix France).
- Mention claire dans l'app : « Estimations, pas un avis médical. »
- Coût IA maîtrisé : appels sur action explicite de l'utilisateur, sauf deux cas bornés :
  recettes générées en arrière-plan (spec 010) et reprise d'une action interrompue par la perte
  de réseau (spec 017, FR-1702).
- Compte Apple Developer gratuit pour l'instant : une exigence qui demande un compte payant
  (iCloud, vente App Store) reste spécifiée mais marquée bloquée, pas abandonnée.

## Workflow de développement

- Flux Spec Kit : constitution → specify → clarify (si besoin) → plan → tasks → implement.
- Chaque feature : spec dans `specs/NNN-nom/`, user stories priorisées et testables seules.
- Code écrit avant sa spec : spec rédigée a posteriori d'après le code, marquée comme telle.
- Exigence remplacée par une spec plus récente : annotée en place (« Remplacée par … »), jamais
  supprimée.
- Commits Conventional Commits.

## Governance

- Cette constitution prime sur toute autre pratique du projet.
- Amendement : modification de ce fichier, Sync Impact Report à jour, version incrémentée
  (MAJOR : principe retiré ou redéfini ; MINOR : principe ou section ajouté ; PATCH : wording).
- Chaque plan (`/speckit-plan`) MUST passer le « Constitution Check » avant implémentation.

**Version**: 2.0.0 | **Ratified**: 2026-11-11 | **Last Amended**: 2026-11-27
