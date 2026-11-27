# Spec 015 : jeûne intermittent

Rédigée a posteriori le 2026-11-27 d'après le code.

## Problème
Repas proposés de 7:00 à 21:00 : incompatibles avec une fenêtre de repas (ex. 16/8).

## Exigences
- FR-1501 : Préférences, section « Jeûne » : interrupteur « Jeûne intermittent » ; activé, fenêtre par défaut
  12:00-19:30 ; heures « Premier repas » et « Dernier repas » à la minute.
- FR-1502 : fenêtre sur une même journée, en minutes depuis minuit (`eatingWindowStartMinutes`,
  `eatingWindowEndMinutes`, SchemaV9, migration légère depuis V8) ; absente = pas de jeûne.
- FR-1503 : écart minimal de 4 h : premier repas ramené entre 00:00 et 19:59, dernier repas entre premier
  + 4 h et 23:59 ; déplacer une heure trop près de l'autre repousse le dernier repas.
- FR-1504 : pied de section : « Repas entre … et …, Xh de jeûne. S'applique aux prochains plannings. »
  (jeûne = 24 h − fenêtre).
- FR-1505 : `eating_window` « HH:mm-HH:mm » envoyé à l'IA. Règle du prompt : tous les repas dans la fenêtre,
  bornes incluses ; pas de breakfast si la fenêtre commence après 10:00 (premier repas = lunch, complété de
  snacks) ; repas du soir pas plus lourd que le déjeuner.
- FR-1506 : jour généré : heures gardées si toutes dans la fenêtre ; sinon toutes réparties à intervalles
  réguliers du premier au dernier repas, dans l'ordre des heures proposées (sans heure : en dernier),
  arrondies au quart d'heure inférieur, jamais avant le début. Correction signalée (`mealTimesFitted`).
- FR-1507 : repas remplacé seul : heure bornée à la fenêtre, les autres repas du jour inchangés.

## Hors champ
- Fenêtre à cheval sur minuit.
- Plannings existants : non recalés.
- Règle « pas de breakfast après 10:00 » : laissée à l'IA, non vérifiée par l'application.
