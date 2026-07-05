#!/usr/bin/env bash
# Vigila CPU, RAM y disco. Si algo supera el umbral avisa por Discord (si esta configurado).
set -euo pipefail
set -a; source /etc/mc/env; set +a

notify() {
  local msg="$1"
  logger -t mc-monitor "$msg"
  if [ -n "${DISCORD_WEBHOOK:-}" ]; then
    curl -sf -H "Content-Type: application/json" \
      -d "{\"content\": \"⚠️ **[$SERVER_NAME]** $msg\"}" \
      "$DISCORD_WEBHOOK" >/dev/null || true
  fi
}

# CPU: uso = 100 - %idle promedio en 2 muestras de 1s
read -r _ a b c prev_idle rest < <(grep '^cpu ' /proc/stat)
prev_total=$((a + b + c + prev_idle))
sleep 1
read -r _ a b c idle rest < <(grep '^cpu ' /proc/stat)
total=$((a + b + c + idle))
cpu=$(( 100 * ( (total - prev_total) - (idle - prev_idle) ) / (total - prev_total) ))

# RAM
mem=$(free | awk '/^Mem:/ {printf "%d", $3/$2*100}')

# Disco raiz
disk=$(df --output=pcent / | tail -1 | tr -dc '0-9')

alerts=""
[ "$cpu"  -ge "$CPU_THRESHOLD"  ] && alerts="${alerts}CPU ${cpu}% (umbral ${CPU_THRESHOLD}%). "
[ "$mem"  -ge "$RAM_THRESHOLD"  ] && alerts="${alerts}RAM ${mem}% (umbral ${RAM_THRESHOLD}%). "
[ "$disk" -ge "$DISK_THRESHOLD" ] && alerts="${alerts}Disco ${disk}% (umbral ${DISK_THRESHOLD}%). "

if [ -n "$alerts" ]; then
  notify "Recursos altos: $alerts"
fi
