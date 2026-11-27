# Plan : spec 023, proxy OpenAI

## Contexte technique
- `backend/`, même crate. Client HTTP : reqwest (rustls, flux). OpenAI simulé dans les tests : serveur axum
  local, URL de base en configuration (`OPENAI_BASE_URL`).
- Configuration : `OPENAI_API_KEY` (absente : route coupée), `OPENAI_BASE_URL`, `OPENAI_MODEL`,
  `OPENAI_MAX_OUTPUT_TOKENS` (16 000), `OPENAI_TIMEOUT_SECONDS` (120), `TICKET_TTL_MINUTES` (15),
  `TICKET_CALLS_*`.

## Constitution Check (2.1.0)
- I : backend limité à la clé IA et au quota. OK.
- II : le serveur ne calcule rien, l'app valide toujours la sortie. OK.
- III : clé côté serveur, `store: false`, aucune requête ni réponse journalisée, aucune donnée stockée hors
  compteurs. OK.
- IV : pas de relais générique ; un seul fournisseur. OK.
- V : comptage des appels testé sur vrai Postgres, concurrence comprise. OK.

## Modèle de données
- `ai_tickets` : `id` uuid PK, `install_id` FK (cascade), `kind` text, `calls` int, `max_calls` int,
  `expires_at` timestamptz, `created_at`.

## Appel (`POST /v1/ai/responses`, en-tête `X-Shreddish-Ticket`)
1. Clé serveur absente : 503.
2. Ticket lu (type) ; nom du schéma admis pour ce type, sinon 400.
3. `UPDATE ai_tickets t SET calls = calls + 1 FROM installs i WHERE t.id = $1 AND t.install_id = $2
   AND i.id = t.install_id AND i.entitlement = 'subscribed' AND i.subscription_expires_at > now
   AND t.calls < t.max_calls AND t.expires_at > now RETURNING t.kind` ; aucune ligne : diagnostic
   (403, 410, 429 ou 402).
4. Corps OpenAI construit (FR-2305), envoi. Échec ou statut non 2xx : `calls - 1`, 502 / 504.
5. Succès : corps renvoyé ; flux : `text/event-stream` transmis tel quel.

## Complexity Tracking
- Aucune abstraction ajoutée : l'URL de base suffit à simuler OpenAI.
