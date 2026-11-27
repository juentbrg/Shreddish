#!/bin/zsh
# Sauvegarde les données de Shreddish (SwiftData) depuis l'iPhone, hors du dépôt.
# Usage : ios/scripts/backup/backup.sh   → ~/Documents/Workspace/poc/perso/Shreddish-backups/<date>
set -euo pipefail
DEVICE=${DEVICE:-00008030-001A5D423C31802E}
DEST=${1:-$HOME/Documents/Workspace/poc/perso/Shreddish-backups/$(date +%Y-%m-%d_%H%M%S)}
mkdir -p "$DEST"
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier app.shreddish --source "Library/Application Support" --destination "$DEST"
ls -la "$DEST"
echo "Sauvegarde : $DEST"
