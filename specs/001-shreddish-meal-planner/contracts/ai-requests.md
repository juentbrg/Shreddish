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

Texte de référence : `PromptBuilder.systemInstructions()`. Enums, unités et format d'heure sont imposés par le
schéma strict ; tirets et rayons sont corrigés par l'application.

- Repas par jour exact, macros à ±5 % (kcal) et ±10 % (glucides, lipides), protéines ≥ cible.
- Allergies, `disliked_foods`, `max_prep_minutes` stricts.
- Budget = objectif ; prix unitaires réalistes selon `store` et `location`.
- Compléments possédés à coût 0, selon `kind` (macro ou dose).
- `infeasible` seulement pour allergies, exclusions ou temps incompatibles, jamais pour le budget ni la longueur.

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
