#!/usr/bin/env bash
# Backup del mundo: vacia buffers via RCON, comprime y sube al blob con Managed Identity.
set -euo pipefail
# set -a: exporta las variables para los procesos hijos (rcon.py las lee de os.environ)
set -a; source /etc/mc/env; set +a

MC_DIR="${MC_DIR:-/opt/mc/server}"
TS=$(date +%Y%m%d-%H%M%S)
ARCHIVE="/tmp/mc-${TS}.tar.gz"

# Si el server esta vivo, fuerza guardado consistente
if systemctl is-active --quiet minecraft; then
  python3 /opt/mc/rcon.py cmd "save-off"       >/dev/null 2>&1 || true
  python3 /opt/mc/rcon.py cmd "save-all flush"  >/dev/null 2>&1 || true
  sleep 5
fi

tar -czf "$ARCHIVE" -C "$MC_DIR" \
  $(cd "$MC_DIR" && ls -d world world_nether world_the_end plugins server.properties 2>/dev/null) \
  2>/dev/null || true

if systemctl is-active --quiet minecraft; then
  python3 /opt/mc/rcon.py cmd "save-on" >/dev/null 2>&1 || true
fi

# Login por Managed Identity y subida
az login --identity --allow-no-subscriptions -o none 2>/dev/null || az login --identity -o none
az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$BACKUP_CONTAINER" \
  --name "mc-${TS}.tar.gz" \
  --file "$ARCHIVE" \
  --auth-mode login \
  --overwrite >/dev/null

logger -t mc-backup "Backup subido: mc-${TS}.tar.gz"
rm -f "$ARCHIVE"
