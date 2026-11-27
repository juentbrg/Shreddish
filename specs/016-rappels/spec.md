# Spec 016 : rappels locaux

Rédigée a posteriori le 2026-11-27 d'après le code.

## Problème
Sans rappel, repas, pesées, courses et planification de la suite sont oubliés.

## Exigences
- FR-1601 : cinq rappels locaux, chacun activable (tous actifs par défaut) avec son heure : repas (à l'heure,
  ou 10, 15, 30, 45, 60 min avant ; 0 par défaut), pesée 08:00, suite du planning 18:00, batch cooking 10:00,
  courses 10:00.
- FR-1602 : réglages propres à l'appareil (UserDefaults `notificationSettings`, hors base) ; champ absent
  = valeur par défaut.
- FR-1603 : repas : chaque repas prévu (ni mangé ni sauté) d'un planning actif, avec heure ; titre
  « Type[ dans N min] · HH:mm », corps = nom du plat.
- FR-1604 : pesée : chaque jour sans pesée enregistrée ; « Pesée du matin ».
- FR-1605 : suite du planning : veille du dernier jour planifié (tous plannings actifs) ; si l'heure est
  passée, le dernier jour même (« Dernier jour de ton planning »).
- FR-1606 : batch cooking : jour de chaque session (début du planning + décalage), corps « titre · durée min ».
- FR-1607 : courses : premier jour de chaque planning, s'il reste des articles non cochés (nombre affiché).
- FR-1608 : seuls les rappels à venir, sur 7 jours (aujourd'hui compris) ; 60 au plus, les plus proches
  (iOS en garde 64).
- FR-1609 : tous les rappels en attente remplacés au lancement, à chaque passage au premier plan ou en
  arrière-plan, après un changement de réglage et après une action Mangé/Sauté ; rien si non autorisé.
- FR-1610 : autorisation (alerte, son, pastille) demandée une fois, au lancement ou à l'ouverture des réglages,
  si un profil existe et qu'au moins un rappel est actif. Refusée : bouton « Autoriser dans Réglages iOS ».
- FR-1611 : rappel de repas : actions « Mangé » et « Sauté », statut du repas mis à jour sans ouvrir l'app.
- FR-1612 : toucher d'un rappel : repas → sa fiche dans Semaine ; suite → feuille « Planifier » sous le
  dernier planning ; batch cooking → sessions du planning ; pesée → « Modifier mon profil » depuis Cible ;
  courses → onglet Courses.
- FR-1613 : rappels affichés aussi app ouverte (bannière, son) ; regroupés par nature.
- FR-1614 : aucune demande ni rappel en tests d'interface.

## Hors champ
- Rappels distants (push).
