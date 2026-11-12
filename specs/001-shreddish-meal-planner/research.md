# Research: Shreddish — planificateur de repas

Phase 0. Chaque décision : choix, raison, alternatives écartées.

## R1. UI et plateforme

- **Decision**: SwiftUI, iOS 26.0 minimum, iPhone seulement, Swift 6 (strict concurrency).
- **Rationale**: Stack Apple native (constitution IV). iOS 26 couvre l'appareil perso et donne
  SwiftData mature + Observation. Environnement local : Xcode 27.2, Swift 6.4, simulateur iOS 27.
- **Alternatives**: UIKit (plus verbeux), React Native / Flutter (dépendances, contraire à IV).

## R2. Persistance

- **Decision**: SwiftData, store local unique, pas de CloudKit.
- **Rationale**: Natif, intégré à SwiftUI (`@Query`), suffisant pour un seul utilisateur et
  quelques milliers d'objets. Données locales seulement (constitution III).
- **Alternatives**: Core Data (plus verbeux), GRDB/SQLite (dépendance tierce), fichiers JSON
  (requêtes et migrations manuelles).

## R3. Stockage clé API

- **Decision**: Keychain via framework `Security`, classe `kSecClassGenericPassword`,
  accessibilité `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, petit wrapper maison.
- **Rationale**: Exigence constitution III et FR-019. `ThisDeviceOnly` : aucune sortie via
  sauvegarde iCloud.
- **Alternatives**: KeychainAccess (dépendance inutile), UserDefaults (non sécurisé, interdit).

## R4. Appel IA

- **Decision**: API OpenAI Responses (`POST https://api.openai.com/v1/responses`) via
  `URLSession` + `async/await`, sortie structurée `text.format` de type `json_schema` avec
  `strict: true`. Modèle configurable dans les réglages, défaut défini dans une constante
  unique (`AIConfig.defaultModel`) à vérifier au moment de l'implémentation.
- **Rationale**: Sortie JSON garantie conforme au schéma : parsing fiable, moins de retries.
  Pas de SDK : un seul endpoint, `URLSession` suffit (constitution IV).
- **Alternatives**: Chat Completions (legacy), SDK Swift tiers (dépendance), sortie texte libre
  + parsing (fragile).
- **Timeouts**: 90 s par requête ; génération semaine découpée si besoin (voir R5).

## R5. Stratégie de génération

- **Decision**: Une requête pour la semaine complète (7 jours) ; repli automatique en 7
  requêtes parallèles d'un jour si timeout ou réponse invalide. Remplacement d'un repas et
  régénération d'un jour : requêtes dédiées avec le contexte du jour (autres repas, cible
  restante).
- **Rationale**: SC-003 (< 60 s) ; une requête = cohérence de variété et de batch cooking ;
  repli = robustesse.
- **Alternatives**: Toujours 7 requêtes (variété moins bonne, batch cooking impossible),
  streaming (complexité UI sans gain réel).

## R6. Validation des sorties IA

- **Decision**: Validation locale en 3 niveaux après décodage :
  1. Structure : 7 jours, nombre de repas conforme aux préférences, champs obligatoires.
  2. Cohérence : |kcal − (4P + 4G + 9L)| ≤ 10 % par repas ; sinon kcal recalculé depuis macros.
  3. Contraintes : temps ≤ max, aucun ingrédient exclu (comparaison normalisée, sans accents,
     minuscules), écart jour ≤ 10 % (signalé, pas rejeté), coût jour ≤ 110 % du budget
     (signalé, pas rejeté).
  4. Batch cooking : actif → 1 à 2 `prep_sessions` (sinon fatal) ; inactif → 0 session et
     tout `prep_session_ref` à null (sinon corrigé) ; chaque `prep_session_ref` non null pointe
     une session existante (sinon fatal).
  `infeasible` non null : pas de validation, raison remontée telle quelle.
  Échec niveau 1 ou exclusion trouvée : rejet + 1 retry automatique, puis erreur affichée.
- **Rationale**: Constitution II, FR-011, SC-004/005.
- **Alternatives**: Confiance aveugle (contraire à II), base nutritionnelle officielle type
  Ciqual (hors v1, cf. Assumptions spec).

## R7. Calculs nutritionnels

- **Decision**:
  - BMR Mifflin-St Jeor : `10·poids + 6,25·taille − 5·âge + s`, s = +5 homme, −161 femme.
  - TDEE = BMR × facteur : 1,2 / 1,375 / 1,55 / 1,725 / 1,9.
  - Objectif : sèche −20 %, prise de masse +10 %, recomposition 0 %.
  - Plancher : 1500 kcal homme, 1200 kcal femme ; et jamais < BMR en sèche (le max des deux).
  - Protéines 2,0 g/kg (sèche, recompo) / 1,8 g/kg (masse) ; lipides 0,8 g/kg min ;
    glucides = reste / 4 ; si reste < 0 : lipides réduits jusqu'à 0,6 g/kg (jamais moins),
    alerte ; glucides plancher 0.
  - Arrondis : kcal à l'unité, grammes à l'unité, en fin de calcul seulement.
- **Rationale**: Formules standard, vérifiables, testables (constitution II, V).
- **Alternatives**: Harris-Benedict (moins précise), Katch-McArdle (nécessite % masse grasse :
  option future).

## R8. Tests

- **Decision**: Swift Testing (`import Testing`) pour la logique. Logique métier dans un
  Swift Package local `ShreddishCore` (sans dépendance UI ni SwiftData) : `swift test` en CLI,
  rapide, TDD (constitution V). Tests UI XCUITest limités au parcours onboarding.
- **Alternatives**: XCTest seul (plus verbeux), tout dans la cible app (tests lents, simulateur
  obligatoire).

## R9. Génération du projet Xcode

- **Decision**: XcodeGen (`ios/project.yml`), `.xcodeproj` non versionné, SwiftLint en
  pré-build. Configuration reprise de Nowtick (`SWIFT_STRICT_CONCURRENCY: complete`,
  String Catalogs, portrait, iPhone seul).
- **Rationale**: Projet lisible et diffable, régénérable en CLI, outil déjà installé. Outil de
  build seulement, aucune dépendance runtime.
- **Alternatives**: `.xcodeproj` versionné (conflits, illisible), Tuist (plus lourd).

## R10. Coûts et rayons

- **Decision**: Coût et rayon estimés par l'IA (prix moyens France), rayon parmi une liste
  fermée : fruits-legumes, viande-poisson, cremerie, epicerie, surgeles, boulangerie, autre.
- **Rationale**: Agrégation liste de courses fiable via enum ; pas de base de prix en v1.

## R11. Agrégation liste de courses

- **Decision**: Fusion par (nom normalisé, unité). Normalisation : minuscules, sans accents,
  trim, espaces multiples réduits ; par mot de plus de 3 lettres : « ux » → « u »,
  « s » final retiré sauf « ss » (« noix » reste « noix »). Unités normalisées : g, ml, pièce.
  Conversion kg → g et l → ml à la validation. Unités différentes pour un même nom : lignes
  séparées.
- **Rationale**: FR-015, simple et déterministe, testable.

## R12. Horloge et jours locaux

- **Decision**: `AppClock` injectable (`now()`, calendrier, fuseau) + `LocalDay` (jour civil
  local), repris de Nowtick `PlannerCore/Model`. Planning = `LocalDay(today) … +6`.
- **Rationale**: Règles dépendantes de la date (J à J+6, adhérence après 21 h, pesée unique par
  jour, tendance poids) testables sans attendre ni changer l'heure système ; changements d'heure
  gérés par le calendrier.
- **Alternatives**: `Date()` direct (tests non déterministes).

## R13. Clé API en développement

- **Decision**: Comme Nowtick (`MISTRAL_DEV_KEY`) : `ios/Config/Secrets.xcconfig` git-ignoré,
  `OPENAI_DEV_KEY` exposée via Info.plist en build Debug seulement ; au premier lancement Debug,
  si Keychain vide, clé copiée dans le Keychain. Build Release : jamais lue.
- **Rationale**: Pas de ressaisie à chaque réinstallation simulateur ; constitution III
  respectée (rien de versionné, Keychain reste la source en usage).
- **Alternatives**: Ressaisie manuelle à chaque install (friction en dev).

## R14. Schéma SwiftData versionné

- **Decision**: `SchemaV1: VersionedSchema` + `ShreddishMigrationPlan` dès la v1, modèles dans
  `ShreddishCore/Model` (pattern Nowtick SchemaV1–V3).
- **Rationale**: Évolutions futures sans perte de données (historique de sèche, pesées).
