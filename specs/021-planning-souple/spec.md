# Spec 021 : planning souple, aliments bannis, restes, foyer et design

Rédigée a posteriori le 2026-11-27 d'après le code (commits « Période à planifier », « Restes proposés en liste
à cocher », « Remplacer d'un coup les repas contenant un aliment banni », « Palette Couleurs du marché »…).

## Problème
Fonctions livrées sans spec : période de moins de 7 jours, navigation entre semaines, bannissement d'aliments,
annulation d'un remplacement, restes à écouler par jour, version surgelée des produits, budget du foyer, design.

## Exigences

### Période et semaines
- FR-2101 : nouvelle période de 1 à 7 jours : « Premier jour » (par défaut « Suite du planning », sinon
  aujourd'hui, jusqu'à J+13 : spec 006) et « Dernier jour ». Budget de la génération au prorata
  (budget hebdo × jours / 7).
- FR-2102 : seuls les jours couverts par la période sont remplacés. Jours d'un planning existant hors période :
  inchangés, toujours actifs ; jours d'après la période séparés dans leur propre planning (un planning coupé au
  milieu donne trois plannings actifs). Planning entièrement couvert : historique, intact. Jours couverts déjà
  commencés (aujourd'hui) : historique ; repas cochés et extras repris dans le nouveau planning. Jours couverts
  futurs, jamais mangés : supprimés.
- FR-2103 : Semaine et Courses : navigation par balayage entre semaines, historique compris (plannings passés
  sans chevauchement, puis plannings actifs). Semaine affichée par défaut : celle d'aujourd'hui, sinon la
  prochaine, sinon la plus récente. Remplace la bascule « En cours / À venir » (spec 006 US1.3).

### Repas
- FR-2104 : après « Remplacer ce repas », carte « Remettre l'ancien repas » : restaure repas, recette, statut,
  part mangée et date du statut. Une seule annulation, celle du dernier remplacement.
- FR-2105 : appui long sur un ingrédient (détail du repas) ou un article de courses : « Ne plus jamais
  proposer » ajoute l'aliment aux aliments exclus (comparaison sans accents ni pluriel). Détection aussi par le
  libellé du produit acheté.
- FR-2106 : repas à venir encore prévus contenant un aliment exclu : bandeau « Remplacer les N repas » dans la
  Semaine, remplacement un à un.
- FR-2107 : carte repas de la Semaine : statut visible, coche verte si mangé, croix et nom barré si sauté.

### Restes à écouler
- FR-2108 : nouvelle période : restes proposés en liste à cocher (paquets entamés du dernier planning, spec 013
  FR-1307, et ingrédients des repas non mangés), cochés par défaut, décochés en place, jamais supprimés.
  Saisie libre en plus.
- FR-2109 : « Régénérer cette journée » : ingrédients des repas non mangés des 3 derniers jours proposés de même.

### Courses et prix
- FR-2110 : ingrédient nommé surgelé d'un produit frais, hors produit à la pièce : ligne à part au rayon
  surgelés, sachets de 750 g ou 1 kg, reste non périssable. Prix : celui des légumes surgelés seulement pour les
  fruits et légumes, et seulement s'il est plus bas que le frais ; viande, poisson et autres gardent leur propre
  prix au kg.
- FR-2111 : carte du ticket : « Reste à acheter » = prix des articles non cochés, barre d'avancement.
- FR-2112 : coût de la semaine (paquets entiers moins restes qui se gardent, spec 013 FR-1305), sur tous les
  repas (spec 019 FR-1904) : même mesure dans la Semaine, les Courses et la carte partagée, comparée au budget de
  la période (FR-2101). Génération : même mesure pour une portion, sans restes reportés de la semaine d'avant ;
  jours comparés à leur part du plafond ramenée au coût des repas. Ticket réel comparé à la liste à acheter.

### Foyer et préférences
- FR-2113 : foyer (spec 017 FR-1704) : quantités des courses × portions du foyer ; budget envoyé à l'IA et
  contrôlé par portion (budget ÷ portions).
- FR-2114 : goût de chaque complément (texte libre, ex. « chocolat ») saisi dans les préférences, envoyé à l'IA
  et repris dans les recettes ; complément sucré jamais dans un plat salé.
- FR-2115 : modèle OpenAI modifiable dans Réglages → Préférences repas (champ libre) ; ancien modèle par défaut
  migré vers le nouveau.

### Design
- FR-2116 : direction « Marché » : palette « Couleurs du marché », polices Bricolage Grotesque (titres) et
  DM Sans (texte), cartes arrondies, mode sombre. Même design sur Semaine, Journal, Courses, Recettes, Profil.
- FR-2117 : grand écran (iPhone Duo, iPad en compatibilité) : largeur de lecture bornée, colonne latérale pour
  le détail d'un repas.

## Hors champ
- Annulation de plusieurs remplacements successifs.
- Journal par membre du foyer.
