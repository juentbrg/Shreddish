<!--
Sync Impact Report
- Version : template → 1.0.0 (adoption initiale)
- Principes ajoutés : I. Usage personnel d'abord ; II. Calculs déterministes, IA en suggestion ;
  III. Données locales et secrets protégés ; IV. Simplicité (YAGNI) ; V. Calculs testés d'abord
- Sections ajoutées : Contraintes techniques ; Workflow de développement ; Governance
- Sections retirées : aucune
- TODO différés : aucun
-->

# Shreddish Constitution

## Core Principles

### I. Usage personnel d'abord

Shreddish (shred + dish) sert un seul utilisateur : son auteur, sur son iPhone.
- Aucun compte, aucun backend propre, aucune fonctionnalité multi-utilisateur ou sociale.
- Chaque fonctionnalité MUST servir directement l'objectif : manger simple, pas cher, rapide,
  aligné sur l'objectif physique (sèche, prise de masse, recomposition).
- Une fonctionnalité sans usage hebdomadaire réel attendu est refusée.

### II. Calculs déterministes, IA en suggestion

- Besoins caloriques et macros MUST provenir de formules reconnues, codées et vérifiables
  (ex. Mifflin-St Jeor + facteur d'activité). Jamais calculés par l'IA.
- L'IA génère seulement des idées de repas et de plannings. Ses sorties MUST être validées
  (format, valeurs nutritionnelles plausibles, écart aux cibles) avant affichage.
- Panne ou absence d'IA : calculateur et planning existant restent utilisables.

### III. Données locales et secrets protégés

- Profil, plannings, historique : stockés sur l'appareil seulement.
- Clé API OpenAI MUST venir de `ios/Config/Secrets.xcconfig` (git-ignoré), copiée dans l'app au
  build (spec 009). Jamais dans le code, le repo, les logs ni un fichier de config versionné.
  Ouverture à d'autres utilisateurs : clé sur un serveur intermédiaire, jamais dans l'app.
- Seules données envoyées à l'IA : celles nécessaires à la génération (cibles, préférences,
  contraintes). Aucune donnée d'identité.

### IV. Simplicité (YAGNI)

- Stack Apple native, dépendances tierces seulement si justifiées dans le plan.
- Pas d'abstraction spéculative : un seul fournisseur IA tant qu'un second n'est pas demandé.
- Toute complexité ajoutée MUST être justifiée dans la section « Complexity Tracking » du plan.

### V. Calculs testés d'abord (NON-NEGOTIABLE)

- Calculs nutritionnels (BMR, TDEE, ajustement objectif, répartition macros, totaux de
  planning) : tests unitaires écrits avant l'implémentation, avec valeurs de référence connues.
- Parsing et validation des réponses IA : testés sur réponses valides, invalides et tronquées.

## Contraintes techniques

- Plateforme : iOS uniquement, iPhone, version iOS récente (cible définie au plan).
- Interface en français.
- Mention claire dans l'app : outil d'aide personnel, pas un avis médical ni diététique.
- Coût IA maîtrisé : appels seulement sur action explicite de l'utilisateur.

## Workflow de développement

- Flux Spec Kit : constitution → specify → clarify (si besoin) → plan → tasks → implement.
- Chaque feature : spec dans `specs/NNN-nom/`, user stories priorisées et testables seules.
- Commits Conventional Commits.

## Governance

- Cette constitution prime sur toute autre pratique du projet.
- Amendement : modification de ce fichier, Sync Impact Report à jour, version incrémentée
  (MAJOR : principe retiré ou redéfini ; MINOR : principe ou section ajouté ; PATCH : wording).
- Chaque plan (`/speckit-plan`) MUST passer le « Constitution Check » avant implémentation.

**Version**: 1.0.0 | **Ratified**: 2026-11-11 | **Last Amended**: 2026-11-11
