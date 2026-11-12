# Contrat : requêtes IA (OpenAI Responses API)

Endpoint : `POST https://api.openai.com/v1/responses`
Headers : `Authorization: Bearer <clé Keychain>`, `Content-Type: application/json`.
Timeout : 90 s. Schémas de sortie : [ai-meal.schema.json](./ai-meal.schema.json).

## Corps commun

```json
{
  "model": "<Preferences.aiModel>",
  "instructions": "<prompt système, voir ci-dessous>",
  "input": "<contexte utilisateur JSON sérialisé>",
  "text": {
    "format": {
      "type": "json_schema",
      "name": "<WeekPlanResponse | DayPlanResponse | MealReplacementResponse>",
      "strict": true,
      "schema": { "...": "schéma correspondant" }
    }
  }
}
```

Extraction de la sortie : premier item `output[]` de type `message`, contenu `output_text`,
décodé en JSON puis validé (research R6).

## Prompt système (résumé des règles imposées)

- Repas simples, ingrédients de supermarché français courants, budget serré.
- Respect strict : `max_prep_minutes`, `excluded_foods` (aucune trace), nombre de repas / jour
  (collations incluses dans `meals_per_day`), coût jour ≤ `daily_budget_eur`.
- `day_offset` 0 = jour de génération ; jours 0 à 6.
- Totaux journaliers à ±5 % de la cible kcal ; protéines ≥ cible.
- Valeurs nutritionnelles cohérentes : kcal ≈ 4P + 4G + 9L.
- Quantités en g, ml ou pièce, crues / non cuites.
- Variété : même plat principal max 2 fois / semaine (sauf batch cooking).
- Batch cooking actif : 1–2 `prep_sessions`, repas liés via `prep_session_ref`.
- Contraintes impossibles : remplir `infeasible`, ne jamais ignorer une contrainte.
- Réponse en français.

## Contexte utilisateur (input)

Données envoyées, rien d'autre (FR-021) :

```json
{
  "task": "week | day | replace_meal",
  "targets": { "kcal": 2100, "protein_g": 160, "carbs_g": 210, "fat_g": 65 },
  "goal": "cut",
  "preferences": {
    "meals_per_day": 4, "max_prep_minutes": 20,
    "daily_budget_eur": 8, "excluded_foods": [], "liked_foods": [],
    "equipment": [], "batch_cooking": false
  },
  "day_offset": 2,
  "existing_day_meals": [ "...repas du jour conservés, pour task=replace_meal" ],
  "meal_type_to_replace": "lunch",
  "remaining_targets": { "kcal": 650, "protein_g": 50, "carbs_g": 60, "fat_g": 20 },
  "avoid_meal_names": [ "...noms déjà présents dans la semaine" ]
}
```

Champs `day_offset`, `existing_day_meals`, `meal_type_to_replace`, `remaining_targets` :
seulement pour `day` et `replace_meal`.

## Erreurs

| Cas | Détection | Comportement |
|---|---|---|
| Pas de clé | Keychain vide | `AIError.missingKey`, renvoi vers réglages |
| 401 | HTTP status | `AIError.invalidKey` |
| 429 | HTTP status | `AIError.rateLimited` (quota / débit), pas de retry auto |
| 5xx / timeout | status / URLError | 1 retry ; semaine : repli 7 requêtes jour (R5) |
| Pas de réseau | URLError.notConnectedToInternet | `AIError.offline` |
| `status: incomplete` / refus | champ réponse | `AIError.incomplete`, 1 retry |
| JSON invalide / validation KO | décodage / validateur | 1 retry, puis `AIError.invalidOutput` |
| `infeasible` non null | champ | `AIError.infeasible(reason)` affichée telle quelle |

Clé jamais loggée ; corps de requête loggé seulement en DEBUG, sans header.

## Test de clé (FR-019)

`GET https://api.openai.com/v1/models` avec la clé : 200 = valide, 401 = invalide.
