#!/usr/bin/env bash
# Instala y configura PaperMC + Geyser + Floodgate. Lo ejecuta cloud-init en el primer arranque.
set -euo pipefail
set -a; source /etc/mc/env; set +a

MC_DIR=/opt/mc/server
PLUGINS_DIR="$MC_DIR/plugins"

id minecraft &>/dev/null || useradd -r -m -d /opt/mc -s /usr/sbin/nologin minecraft
mkdir -p "$PLUGINS_DIR"

# --- PaperMC (ultima version con build STABLE, via API Fill v3; la v2 murio con 410) ---
PROJECT=paper
UA="mc-azure-setup/1.0"
PAPER_URL=""
for VER in $(curl -sfA "$UA" "https://fill.papermc.io/v3/projects/$PROJECT/versions" | jq -r '.versions[].version.id'); do
  PAPER_URL=$(curl -sfA "$UA" "https://fill.papermc.io/v3/projects/$PROJECT/versions/$VER/builds" \
    | jq -r '[.[] | select(.channel=="STABLE")][0].downloads["server:default"].url // empty')
  [ -n "$PAPER_URL" ] && break
done
[ -n "$PAPER_URL" ] || { echo "No se encontro build STABLE de Paper" | logger -t mc-setup; exit 1; }
curl -sfL -A "$UA" -o "$MC_DIR/paper.jar" "$PAPER_URL"
echo "Paper $VER instalado desde $PAPER_URL" | logger -t mc-setup

# --- Geyser + Floodgate (para jugadores Bedrock) ---
curl -sL -o "$PLUGINS_DIR/Geyser-Spigot.jar"    "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
curl -sL -o "$PLUGINS_DIR/floodgate-spigot.jar" "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"

# --- EULA ---
echo "eula=true" > "$MC_DIR/eula.txt"

# --- server.properties ---
cat > "$MC_DIR/server.properties" <<EOF
server-port=25565
enable-rcon=true
rcon.port=${RCON_PORT}
rcon.password=${RCON_PASSWORD}
broadcast-rcon-to-ops=false
max-players=${MAX_PLAYERS}
online-mode=true
motd=Servidor de Minecraft (Java + Bedrock)
view-distance=8
simulation-distance=6
spawn-protection=0
enable-query=false
EOF

# --- Config de Geyser (auth via Floodgate: Bedrock entra sin cuenta Java) ---
mkdir -p "$PLUGINS_DIR/Geyser-Spigot"
cat > "$PLUGINS_DIR/Geyser-Spigot/config.yml" <<EOF
bedrock:
  address: 0.0.0.0
  port: 19132
  clone-remote-port: false
remote:
  address: 127.0.0.1
  port: 25565
  auth-type: floodgate
  use-proxy-protocol: false
passthrough-motd: true
EOF

chown -R minecraft:minecraft /opt/mc

systemctl daemon-reload
systemctl enable --now minecraft.service
systemctl enable --now mc-monitor.timer mc-idle-stop.timer mc-backup.timer
logger -t mc-setup "Setup completado."
