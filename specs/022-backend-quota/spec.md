# Spec 022 : backend, lot 1 (installations, quota IA, droits)

Créée le 2026-11-27. Premier lot du backend (`backend/`, constitution 2.1.0, principes I et III).
Essai révisé le 2026-11-27 : offre d'introduction Apple d'une semaine au lieu d'une action IA gratuite
(FR-2208, FR-2209) ; code du lot à aligner (tâches T015 à T017).

## Problème
La clé OpenAI est dans l'app (spec 009) : extractible, coût IA sans plafond, essai gratuit perdu à la
réinstallation (spec 017 FR-1715, partiel). Avant toute distribution publique, la clé doit passer côté serveur
avec un quota par installation. Ce lot prépare ce serveur sans encore sortir la clé : l'app iOS n'est pas
modifiée, le développement reste possible sans lancer le serveur.

## User stories

### US1 (P1) : une installation obtient une identité anonyme
Au premier besoin, l'app enregistre son installation et reçoit un jeton secret ; aucun compte, aucune donnée
personnelle.
- Étant donné une app sans jeton, quand elle s'enregistre, alors elle reçoit un identifiant et un jeton
  qu'elle seule connaît.
- Étant donné un jeton faux, révoqué ou absent, quand l'app appelle un service protégé, alors refus
  « non authentifié ».

### US2 (P1) : le coût IA est plafonné par installation
Chaque action IA consomme une unité du quota du jour pour son type ; au-delà de la limite, refus.
- Étant donné une limite de 3 semaines par jour, quand une installation en consomme 3, alors la 4e est
  refusée avec l'heure de remise à zéro.
- Étant donné 1 unité restante et 10 demandes simultanées, alors une seule est acceptée.
- Étant donné un nouveau jour, alors le compteur repart de zéro.
- L'app peut lire ce qui reste pour chaque type, sans rien consommer.

### US3 (P2) : droits d'accès gardés côté serveur
Essai gratuit = offre d'introduction d'une semaine de l'abonnement, gérée par Apple (spec 017 FR-1715) :
une fois par identifiant Apple, réinstaller ou changer d'appareil ne le rend pas. Le serveur ne gère aucun
essai : une transaction d'essai est un abonnement actif jusqu'à sa date d'expiration.
- Étant donné une installation sans preuve d'achat, quand elle demande une action IA, alors refus
  « abonnement requis ».
- Étant donné une preuve d'essai ou d'abonnement valide, quand l'app la transmet, alors l'installation est
  abonnée jusqu'à la date d'expiration fournie, avec le quota quotidien.
- Étant donné un essai annulé ou un abonnement expiré, alors refus « abonnement requis ».

### US4 (P3) : service exploitable
- État du service et de sa base consultable sans jeton.
- Toute erreur a la même forme (code stable, message), chaque requête est tracée avec un identifiant.

## Exigences
- FR-2201 : enregistrement d'une installation : identifiant aléatoire et jeton secret aléatoire (≥ 256 bits).
  Jeton stocké sous forme d'empreinte seulement ; perdu = nouvelle installation.
- FR-2202 : services protégés : jeton porteur exigé ; installation inconnue ou révoquée : refus
  « non authentifié ».
- FR-2203 : types d'action IA : `week` (semaine générée), `meal` (repas remplacé), `day` (jour régénéré),
  `recipe` (recette). Type inconnu : refus « requête invalide ».
- FR-2204 : limite quotidienne par type, en configuration du serveur (pas dans le code). Valeurs non
  arrêtées (spec 017, « À décider ») : défaut de dev `week` 3, `meal` 30, `day` 10, `recipe` 60.
- FR-2205 : jour du quota : jour calendaire UTC. Réponse de refus : limite, consommé, remise à zéro (début du
  jour UTC suivant).
- FR-2206 : consommation atomique : jamais lecture puis écriture ; N demandes simultanées pour R unités
  restantes : exactement min(N, R) acceptées.
- FR-2207 : lecture du quota restant par type, sans consommation.
- FR-2208 : droits par installation : `none` (aucune preuve) ou `subscribed` (date d'expiration). Essai
  gratuit = offre d'introduction Apple d'une semaine, vérifiée comme un abonnement (spec 017 FR-1715) ;
  aucun essai géré par le serveur. Abonnement expiré : traité comme `none`.
- FR-2209 : consommation d'une unité IA : autorisée seulement si `subscribed` non expiré, dans la même
  opération que la lecture du droit ; sinon refus « abonnement requis ».
- FR-2210 : preuve d'achat (essai ou abonnement payant) vérifiée par un vérificateur interchangeable. Ce lot :
  vérificateur de dev seul (accepte une preuve de test, essai de 7 jours compris), activé par la configuration,
  jamais en production.
- FR-2211 : erreurs : corps JSON `{"error": {"code", "message"}}` ; codes stables : `unauthenticated`,
  `invalid_request`, `quota_exceeded`, `subscription_required`, `not_found`, `internal`. Aucune trace
  interne dans le message.
- FR-2212 : état du service sans jeton : service vivant et base joignable ; base injoignable : indisponible.
- FR-2213 : chaque requête tracée (méthode, chemin, statut, durée, identifiant de requête renvoyé en
  en-tête). Jamais le jeton dans les traces.
- FR-2214 : schéma de base créé et mis à jour au démarrage du service.
- FR-2215 : aucune donnée de profil, de santé, de repas ni de journal stockée (constitution, principe III).

## Contrat prévu, hors lot : proxy IA
- L'app enverra au serveur la requête de génération (même contenu qu'aujourd'hui vers OpenAI) avec son
  jeton et le type d'action ; le serveur consommera le quota (FR-2206, FR-2209), appellera OpenAI avec sa clé,
  renverra la réponse telle quelle. Quota rendu si l'appel OpenAI échoue.
- Tant que ce proxy n'existe pas : l'app garde sa clé de build (spec 009).

## Critères de succès
- SC-2201 : 1 000 demandes simultanées à la limite : jamais une unité de plus que la limite acceptée.
- SC-2202 : installation sans abonnement : aucune action IA acceptée, quel que soit le nombre de demandes
  simultanées.
- SC-2203 : lecture ou consommation du quota : réponse en moins de 100 ms sur le VPS, base comprise, au 95e
  centile.
- SC-2204 : aucun jeton en clair dans la base ni dans les traces.

## Hypothèses
- Essai lié à l'identifiant Apple (offre d'introduction), pas à l'installation : jeton perdu = nouvelle
  installation, à rattacher en renvoyant la preuve d'achat, sans nouvel essai.
- Offre d'introduction configurable seulement avec un compte payant ; testable en local avec un fichier de
  configuration StoreKit. Lien à l'appareil (App Attest, DeviceCheck) : lot suivant, à vérifier avec un compte gratuit.
- Vérification réelle des achats (App Store Server API) : lot suivant, compte payant probablement requis.
- Une seule instance du serveur, une seule base.

## Hors champ
- Proxy OpenAI (contrat ci-dessus seulement), modification de l'app iOS, app Android.
- Vérification réelle App Store, App Attest, DeviceCheck.
- Comptes utilisateurs, stockage des données de santé ou du journal.
