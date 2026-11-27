# Tâches : spec 022, backend lot 1

## Phase 1 : socle
- [x] T001 Dépendances (sea-orm-migration, tower-http, uuid, chrono, sha2, rand, base64) dans `backend/Cargo.toml`
- [x] T002 `src/error.rs` : AppError, codes FR-2211, réponse JSON
- [x] T003 `src/config.rs` : limites FR-2204, vérificateur, refus de `dev` en production
- [x] T004 Migration `installs` et `ai_usage`, lancée au démarrage (FR-2214)
- [x] T005 Entités SeaORM
- [x] T006 Couches : id de requête en en-tête, traces sans jeton (FR-2213)

## Phase 2 : US1 identité (P1)
- [x] T007 Test : enregistrement, jeton faux / absent / révoqué refusé
- [x] T008 `src/auth.rs` + `POST /v1/installs` (FR-2201, FR-2202)

## Phase 3 : US2 quota (P1)
- [x] T009 Tests sur Postgres : limite, type inconnu, nouveau jour, lecture sans consommation, 1 000 demandes
  simultanées (SC-2201)
- [x] T010 `src/quota.rs` + routes `GET /v1/quota`, `POST /v1/quota/consume` (FR-2203 à FR-2207)

## Phase 4 : US3 droits (P2)
- [x] T011 Tests : essai consommé une fois (concurrence, SC-2202), abonné, expiré, preuve dev
- [x] T012 `src/entitlement.rs` + `POST /v1/entitlements/verify` (FR-2208 à FR-2210)

## Phase 5 : US4 exploitation (P3)
- [x] T013 Test : forme des erreurs, en-tête d'id de requête, /health
- [x] T014 README backend
