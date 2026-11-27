# Plan : spec 022, backend lot 1

## Contexte technique
- Rust 2024, axum 0.8, SeaORM 1.1 (Postgres), sea-orm-migration, tower-http (traces, id de requête).
- Dossier `backend/`, crate unique `shreddish-api` (lib + binaire). Postgres local : `backend/compose.yaml`
  (port 5433, bases `shreddish` et `shreddish_test`).
- Config par variables d'environnement (`.env` en dev, `.env.example` versionné).

## Constitution Check (2.1.0)
- I : aucun compte ; identité = installation anonyme. Backend limité au quota et aux droits. OK.
- II : aucun calcul nutritionnel côté serveur. OK.
- III : aucune donnée de santé ni de journal (FR-2215) ; jeton haché ; clé OpenAI pas encore côté serveur
  (proxy au lot suivant), l'app garde sa clé de build. OK.
- IV : une crate, pas de couche « repository » ; vérificateur d'achats derrière un trait, seule abstraction,
  justifiée (dev aujourd'hui, App Store demain). OK.
- V : quota = calcul de facturation, testé d'abord sur vrai Postgres, concurrence comprise. OK.

## Modèle de données
- `installs` : `id` uuid PK, `token_hash` bytea unique (SHA-256 du jeton), `entitlement` text
  (`none` | `subscribed`), `subscription_expires_at` timestamptz null, `created_at`,
  `revoked_at` null.
- `ai_usage` : `install_id` FK (cascade), `day` date (UTC), `kind` text, `count` int ; PK
  (`install_id`, `day`, `kind`).

## Consommation atomique (FR-2206, FR-2209)
Une transaction :
1. `SELECT … FROM installs WHERE id = $1 FOR UPDATE` : sérialise les demandes d'une installation.
2. Droit : `subscribed` non expiré, sinon refus `subscription_required`.
3. `INSERT INTO ai_usage … VALUES (…, 1) ON CONFLICT DO UPDATE SET count = ai_usage.count + 1
   WHERE ai_usage.count < $limit RETURNING count` : aucune ligne = `quota_exceeded`. Limite 0 : refus avant.
4. Commit.

## API (`/v1`, JSON)
- `POST /v1/installs` → 201 `{install_id, token}`.
- `GET /v1/quota` → `{day, resets_at, entitlement, kinds: {week: {limit, used, remaining}, …}}`.
- `POST /v1/quota/consume` `{kind}` → 200 `{kind, limit, used, remaining}` ; 429 `quota_exceeded` ;
  402 `subscription_required`.
- `POST /v1/entitlements/verify` `{proof}` → 200 `{entitlement, expires_at}`. Vérificateur dev : preuve
  `dev-subscription:<jours>` (essai : `dev-subscription:7`).
- `GET /health` → 200 / 503.
- Erreurs : `{"error": {"code", "message"}}` ; 401, 400, 402, 404, 429, 500.

## Structure
```text
backend/
├── Cargo.toml, compose.yaml, docker-init/, .env.example
├── src/
│   ├── main.rs          # démarrage : config, base, migrations, serveur
│   ├── lib.rs           # AppState, router, couches (traces, id de requête)
│   ├── config.rs        # limites, vérificateur, environnement
│   ├── error.rs         # AppError → JSON
│   ├── auth.rs          # jeton : génération, empreinte, extracteur
│   ├── quota.rs         # types d'action, consommation, lecture
│   ├── entitlement.rs   # droits, trait Verifier, vérificateur dev
│   ├── entities/        # SeaORM : installs, ai_usage
│   ├── migration/       # sea-orm-migration
│   └── routes/          # health, installs, quota, entitlements
└── tests/               # intégration, TEST_DATABASE_URL
```

## Complexity Tracking
- Trait `Verifier` : deux implémentations prévues (dev, App Store). Aucune autre abstraction.
