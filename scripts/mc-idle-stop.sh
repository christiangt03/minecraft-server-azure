#!/usr/bin/env bash
# Si no hay jugadores durante IDLE_MINUTES: hace backup y auto-apaga la VM (deallocate).
set -euo pipefail
# set -a: exporta las variables para los procesos hijos (rcon.py las lee de os.environ)
set -a; source /etc/mc/env; set +a

STATEFILE="/run/mc-empty-since"

# Si el server no esta activo, no hacemos nada (ya estara arrancando o parado)
systemctl is-active --quiet minecraft || exit 0

count=$(python3 /opt/mc/rcon.py list_count 2>/dev/null || echo "err")
if [ "$count" = "err" ]; then
  exit 0   # RCON aun no responde (server arrancando)
fi

if [ "$count" != "0" ]; then
  rm -f "$STATEFILE"
  exit 0
fi

now=$(date +%s)
[ -f "$STATEFILE" ] || echo "$now" > "$STATEFILE"
since=$(cat "$STATEFILE")
idle_min=$(( (now - since) / 60 ))

if [ "$idle_min" -ge "$IDLE_MINUTES" ]; then
  logger -t mc-idle-stop "Sin jugadores ${idle_min} min -> backup y apagado."
  /opt/mc/mc-backup.sh || true
  RID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-02-01&format=text")
  az login --identity -o none
  az vm deallocate --ids "$RID" --no-wait
fi
