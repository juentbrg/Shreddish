# Spec 009 : clé API fournie au build

- FR-901 : clé OpenAI lue depuis `OPENAI_API_KEY` (`ios/Config/Secrets.xcconfig`, git-ignoré), copiée dans l'Info.plist au build, Debug et Release.
- FR-902 : plus aucune saisie, test ni suppression de clé dans l'app ; ancienne clé effacée du trousseau au lancement.
- FR-903 : sans clé dans le build, la semaine affiche « Clé API absente du build » et la génération est indisponible.
- FR-904 : test de génération réelle `AppTests/LiveGenerationTests`, désactivé par défaut (`SHREDDISH_LIVE=1`), rapport JSON optionnel.
- Limite : clé extractible de l'app. Usage perso seulement ; ouverture à d'autres = serveur intermédiaire.
