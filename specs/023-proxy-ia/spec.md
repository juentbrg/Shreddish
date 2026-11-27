# Spec 023 : backend, lot 2 (proxy OpenAI)

Créée le 2026-11-27. Suite de la spec 022. Côté serveur seulement : l'app iOS garde sa clé de build (spec 009)
et n'appelle pas encore le serveur ; branchement de l'app au lot suivant.

## Problème
La clé OpenAI doit quitter l'app (constitution, principe III). Le quota de la spec 022 compte des actions
utilisateur, mais une action fait plusieurs appels OpenAI. Décompte au 2026-11-27, pire cas :
- semaine de N jours : 1 `week` + 18N `day` + (1 + 2N) `foodMatch`, soit 7 + 20N (147 pour 7 jours) ;
- jour régénéré : 12 `day` + 2 `foodMatch` = 14 ;
- repas remplacé : 6 `meal` + 1 `foodMatch` = 7 ;
- recette : 1 `recipe` par repas sans recette (35 au plus après une semaine de 7 jours à 5 repas).

## User stories

### US1 (P1) : une action ouvre un ticket d'appels
Consommer une unité de quota (spec 022 FR-2206) renvoie aussi un ticket : droit à un nombre borné d'appels IA
pour cette action, pendant une durée courte.
- Étant donné une semaine consommée, alors ticket `week` valable 15 min pour 150 appels au plus.
- Étant donné un ticket épuisé, expiré, ou d'une autre installation, alors refus.

### US2 (P1) : l'app appelle l'IA sans clé
L'app envoie la requête de génération au serveur avec son jeton et son ticket ; le serveur appelle OpenAI
avec sa clé et renvoie la réponse telle quelle, en flux si demandé.
- Étant donné un ticket valide, alors réponse d'OpenAI renvoyée, flux compris.
- Étant donné un champ hors liste (modèle, conservation…), alors ignoré : le serveur fixe ces valeurs.
- Étant donné une erreur d'OpenAI, alors erreur propre au serveur, jamais l'erreur OpenAI brute (l'app
  lirait 401 comme « clé invalide »).

### US3 (P2) : un échec d'OpenAI ne coûte rien
- Étant donné un appel en échec côté OpenAI, alors il ne compte pas dans le ticket : nouvel essai possible
  tant que le ticket est valide. Aucune unité de quota rendue (choix produit : l'action reste comptée).

## Exigences
- FR-2301 : consommation (spec 022 FR-2206) : crée dans la même transaction un ticket lié à l'installation et
  au type d'action ; renvoie son identifiant, son expiration et son plafond d'appels.
- FR-2302 : plafond d'appels par type, en configuration : `week` 150, `day` 15, `meal` 8, `recipe` 1.
  Durée de vie : 15 min. Remplacer K repas = K unités `meal`, K tickets.
- FR-2303 : schémas de réponse admis par type de ticket : `week` : `WeekPlanResponse`, `DayPlanResponse`,
  `FoodMatchResponse` ; `day` : `DayPlanResponse`, `FoodMatchResponse` ; `meal` : `MealReplacementResponse`,
  `FoodMatchResponse` ; `recipe` : `RecipeResponse`. Autre schéma : refus « requête invalide », appel non
  compté. `foodMatch` n'a pas de quota propre : toujours dans le ticket d'une action.
- FR-2304 : chaque appel : jeton, ticket, abonnement actif (spec 022 FR-2209) revérifiés ; compteur d'appels
  incrémenté en une opération atomique (N appels simultanés pour R restants : exactement min(N, R) acceptés).
- FR-2305 : requête transmise à OpenAI construite par le serveur à partir des seuls champs admis :
  instructions, entrée, format de sortie (schéma JSON strict), flux. Fixés par le serveur : modèle,
  `store: false`, raisonnement court, plafond de jetons de sortie. Corps de plus de 256 Ko refusé.
- FR-2306 : modèle fixé par le serveur (configuration). En mode serveur, le modèle libre de l'app
  (spec 021 FR-2115) est ignoré.
- FR-2307 : réponse en flux transmise au fil de l'eau, sans mise en mémoire ; client déconnecté : appel à
  OpenAI interrompu.
- FR-2308 : erreurs : OpenAI injoignable ou en erreur : `upstream_error` (502) ; délai dépassé :
  `upstream_timeout` (504) ; clé serveur absente : `ai_unavailable` (503), service IA coupé. Ticket inconnu
  ou d'une autre installation : `ticket_invalid` (403) ; expiré : `ticket_expired` (410) ; épuisé :
  `ticket_exhausted` (429). Appel en échec (502, 504) : décompté du ticket (US3).
- FR-2309 : ni requête ni réponse d'OpenAI dans les traces ; statut et durée seulement.
- FR-2311 : consignes système imposées par le serveur selon le schéma (planning, recette, choix Ciqual) ;
  celles envoyées par l'app sont ignorées. Copies des consignes de l'app (`backend/prompts/`), gardées en phase
  par un test de l'app.
- FR-2312 : entrée contrôlée avant tout appel : JSON de contexte de 32 Ko au plus, tâche conforme au schéma
  (`week`, `day`, `replace_meal`, `recipe`, `food_match`), aucun texte de plus de 1 000 caractères. Refus :
  « requête invalide », appel non compté. Entrées types de l'app (`backend/tests/fixtures/inputs/`) : toutes
  acceptées, vérifié par test.
- FR-2310 : quota `recipe` par défaut relevé à 120 (3 semaines × 35 recettes, plus les recettes ouvertes à
  la main) ; valeurs toujours à arrêter (spec 017, « À décider »).

## Critères de succès
- SC-2301 : aucune requête vers OpenAI sans ticket valide d'une installation abonnée.
- SC-2302 : 20 appels simultanés sur un ticket à 8 appels : exactement 8 transmis.
- SC-2303 : premier fragment du flux reçu par l'app au plus 100 ms après sa réception par le serveur.
- SC-2304 : tests sans appel facturé : OpenAI simulé.

## Décisions (2026-11-27, validées)
- Appel en échec chez OpenAI : non compté dans le ticket ; l'action reste comptée dans le quota du jour.
- Modèle fixé par le serveur ; choix du modèle retiré de l'app (spec 021 FR-2115 remplacée).
- Détournement d'un ticket par une app modifiée : consignes côté serveur et entrée contrôlée (FR-2311,
  FR-2312), sans appel supplémentaire.

## Hypothèses et risques
- Résidu : une question glissée dans un texte court de l'entrée, réponse contrainte au schéma de repas. Valeur
  quasi nulle pour un abus ; App Attest (lot suivant) fermera l'accès aux apps modifiées.
- Motif de refus de l'IA recopié dans l'entrée (spec 008) : plus de 1 000 caractères = requête refusée. L'app
  devra le tronquer en passant par le serveur.
- Schéma de sortie fourni par l'app, seul son nom est contrôlé.

## Hors champ
- Branchement de l'app iOS (lot suivant, avec bascule clé locale / serveur pour le dev).
- Vérification réelle des achats, App Attest.
