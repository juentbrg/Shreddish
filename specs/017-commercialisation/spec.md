# Spec 017 : version commercialisable

## Contexte
App perso fonctionnelle (planning IA, journal, courses, poids, recettes, jeûne, rappels). Cible : vente sur
l'App Store. Clé OpenAI externalisée côté serveur : traitée à part. Exigences ci-dessous obligatoires sauf
mention « option » ou « à décider ».

## Exigences

### Données
- FR-1701 Sauvegarde et synchro iCloud (CloudKit privé) : planning, journal, pesées, recettes, préférences,
  réglages. Restauration automatique sur nouvel iPhone. Migration de la base locale existante sans perte.
  Contraintes CloudKit : attributs optionnels ou avec défaut, aucun `.unique`, relations optionnelles.
- FR-1702 Hors ligne : planning, recettes, journal, courses, pesées consultables et modifiables sans réseau.
  Génération IA en file d'attente, reprise au retour du réseau, sans perte d'une génération interrompue.

### Alimentation
- FR-1703 Régimes : omnivore, végétarien, vegan, pescétarien, halal, casher, sans gluten, sans lactose,
  cumulables. Envoyés à l'IA et vérifiés localement (ingrédients interdits par régime, comme les allergies).
- FR-1704 Foyer : plusieurs personnes, chacune avec profil et cibles (ou portion « invité » simple).
  Repas communs, portions par personne, courses cumulées. Journal et poids par personne.
- FR-1705 Modifier un repas soi-même : ingrédients, quantités, nom, étapes. Macros et coût recalculés
  (Ciqual, prix). Créer une recette perso de zéro, réutilisable comme les recettes sauvegardées.

### Courses
- FR-1706 Partage de la liste (texte, Rappels iOS, lien). Articles cochés reportés d'une semaine à l'autre
  (« déjà acheté »).

### Suivi
- FR-1708 Progrès : mensurations (taille, hanches, poitrine, bras, cuisses), photos privées (stockées sur
  l'appareil et iCloud, jamais envoyées à l'IA), bilan mensuel (poids, tendance, adhérence au plan).
- FR-1709 Apple Santé, **option désactivée par défaut** : lecture du poids et de la dépense active (pour la
  calibration), écriture des apports du journal. Autorisations demandées seulement à l'activation.

- FR-1716 Journal rapide : écart hors planning saisi en secondes. Scan de code-barres (Open Food Facts,
  macros pour 100 g, portion ajustable), recherche Ciqual pour le frais, favoris et récents en un toucher.
  Repas du plan mangé partiellement (½, ¾) ou modifié. Alimente bilan, calibration et rappels.

### Apple Watch et widgets
- FR-1710 Widgets écran d'accueil et verrouillé : prochain repas, kcal et protéines restantes du jour.
- FR-1711 App Apple Watch : repas du jour, cocher mangé / sauté, pesée rapide, complication prochain repas.
  Données partagées avec l'iPhone, utilisable sans iPhone à proximité pour la journée en cours.

### Langues et accessibilité
- FR-1712 Langues : français, anglais, espagnol, allemand, italien (interface, notifications, recettes et
  noms de plats générés dans la langue de l'appareil). Ciqual et prix : France seulement en V1 ; prix
  marqués « estimation France » hors France.
- FR-1713 Accessibilité : VoiceOver complet (libellés, regroupements, ordre), Dynamic Type jusqu'aux
  tailles d'accessibilité sans texte tronqué, contrastes AA, Réduire les animations respecté, cibles 44 pt.

### Juridique
- FR-1714 Politique de confidentialité RGPD et conditions d'utilisation, accessibles dans l'app et sur
  l'App Store. Consentement explicite avant le premier envoi à OpenAI (données envoyées listées). Export et
  suppression des données. Avertissement « pas un avis médical » conservé ; blocage ou alerte pour profils
  à risque (mineurs, IMC bas, grossesse). Conformité aux règles santé de l'App Store (5.1.1, 5.1.3, 1.4.1).

### Abonnement
- FR-1715 Abonnement StoreKit 2 : essai gratuit, mensuel et annuel, restauration des achats, gestion
  depuis l'app. Quota d'appels IA par utilisateur et par jour, côté serveur. Pas d'offre gratuite
  permanente : essai de 7 jours puis abonnement. Un abonnement couvre tout le foyer. Offre de lancement :
  première année annuelle à prix réduit pour les premiers abonnés. **Prix : 9,99 € / mois, 69,99 € / an,
  lancement 49,99 € la première année.**

### Effet « waouh » (acquisition, UGC)
- FR-1717 Première semaine en moins de 60 s après l'accueil : génération montrée en direct (plats qui
  apparaissent jour par jour, total kcal et budget qui se remplissent), avant toute demande de paiement.
- FR-1718 Cartes partageables au format story (9:16) : « ma semaine » (7 jours de plats, kcal, budget),
  ticket de courses estimé contre réel, progrès (courbe, avant / après avec photos si l'utilisateur le
  choisit). Sans donnée sensible par défaut, filigrane discret de l'app.

## À décider
- Coût IA mesuré (gpt-6-luna, 20/11/2026) : semaine + 28 recettes ≈ 0,013 $, repas remplacé
  ≈ 0,001 $, jour régénéré ≈ 0,002 $. Usage intensif ≈ 0,15 $ / mois ; plafond par quota (ex. 3 semaines
  et 30 remplacements par jour) ≈ 2 $ / mois au pire.
- Pistes « waouh » : photo du frigo → ingrédients à écouler et semaine qui les utilise ; photo d'une
  assiette → macros estimées dans le journal.

## Hors champ
- Drives : aucune API publique d'ajout au panier (Carrefour, Leclerc, Intermarché) ; Jow passe par des
  partenariats commerciaux. Ni export ni lien drive en V1.
- Partenariats drives (ajout direct au panier).
- Prix hors France.
