#!/usr/bin/env bash
# Se ejecuta via OnFailure= cuando el servicio de Minecraft falla.
source /etc/mc/env 2>/dev/null || true
MSG="El proceso de Minecraft se ha caido/fallado en $(hostname)."
logger -t mc-crash-alert "$MSG"
if [ -n "${DISCORD_WEBHOOK:-}" ]; then
  curl -sf -H "Content-Type: application/json" \
    -d "{\"content\": \"🛑 **[${SERVER_NAME:-minecraft}]** $MSG\"}" \
    "$DISCORD_WEBHOOK" >/dev/null || true
fi
