# Tâches : spec 023, proxy OpenAI

- [x] T001 Dépendance reqwest ; configuration OpenAI et tickets (`config.rs`)
- [x] T002 Migration `ai_tickets` ; quota `recipe` par défaut 120
- [x] T003 Tests : ticket créé à la consommation, plafond et expiration, 20 appels simultanés à 8 (SC-2302)
- [x] T004 `ticket.rs` : création dans la transaction de consommation, prise d'un appel, restitution
- [x] T005 Tests avec OpenAI simulé : corps filtré et clé serveur, flux, schéma refusé, échec non compté,
  401 d'OpenAI masqué, ticket expiré, d'une autre installation, abonnement expiré, clé absente
- [x] T006 `routes/ai.rs` + erreurs FR-2308
- [x] T007 README, `.env.example`
- [x] T008 Champ « Modèle » retiré des Préférences (vue, générateurs, traductions) ; spec 021 FR-2115 annotée
- [x] T009 Consignes système côté serveur (`backend/prompts/`), test de phase côté app (`PromptExportTests`)
- [x] T010 Contrôle de l'entrée (FR-2312), entrées types de l'app acceptées (`tests/fixtures/inputs/`)
