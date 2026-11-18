#!/bin/zsh
# Réinjecte une sauvegarde dans l'app sur l'iPhone (écrase les données actuelles).
# Usage : tools/backup/restore.sh <dossier de sauvegarde>
set -euo pipefail
DEVICE=${DEVICE:-00008030-001A5D423C31802E}
SRC=${1:?dossier de sauvegarde}
# Fermer l'app avant d'écrire la base.
PID=$(xcrun devicectl device info processes --device "$DEVICE" 2>/dev/null | awk '/Shreddish.app/ {print $1; exit}')
[[ -n "${PID:-}" ]] && xcrun devicectl device process terminate --device "$DEVICE" --pid "$PID" || true
for file in "$SRC"/*; do
  xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier app.shreddish --source "$file" --destination "Library/Application Support/$(basename "$file")"
done
echo "Restauré depuis $SRC"
