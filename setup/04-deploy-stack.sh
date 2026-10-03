#!/bin/bash
# =============================================================================
#  04 — NAS Stack deployen
#  Führt finale Vorbereitungen durch und startet den Docker Compose Stack.
# =============================================================================
set -euo pipefail

NAS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_ROOT="/mnt/data"

echo "=== DietPi NAS Setup — Phase 4: Stack Deploy ==="

# --- Prüfungen ---
if ! mountpoint -q "$DATA_ROOT"; then
    echo "FEHLER: $DATA_ROOT ist nicht gemountet!"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "FEHLER: Docker ist nicht aktiv!"
    exit 1
fi

# --- .env prüfen ---
if [ ! -f "$NAS_DIR/.env" ]; then
    echo "FEHLER: $NAS_DIR/.env fehlt!"
    echo "Kopiere .env.example → .env und passe die Werte an:"
    echo "  cp $NAS_DIR/.env.example $NAS_DIR/.env"
    echo "  chmod 600 $NAS_DIR/.env"
    echo "  nano $NAS_DIR/.env"
    exit 1
fi

# --- Docker-Netzwerk erstellen (falls nicht vorhanden) ---
if ! docker network inspect nas-network >/dev/null 2>&1; then
    docker network create nas-network
    echo "Docker-Netzwerk 'nas-network' erstellt."
fi

# --- Verzeichnisse für Volumes sicherstellen ---
echo "Verzeichnisstruktur prüfen..."
dirs=(
    "$DATA_ROOT/docker-volumes/filebrowser"
    "$DATA_ROOT/docker-volumes/nextcloud-data"
    "$DATA_ROOT/docker-volumes/vaultwarden"
    "$DATA_ROOT/docker-volumes/jellyfin/config"
    "$DATA_ROOT/docker-volumes/jellyfin/cache"
    "$DATA_ROOT/docker-volumes/homepage"
    "$DATA_ROOT/docker-volumes/uptime-kuma"
)
for dir in "${dirs[@]}"; do
    mkdir -p "$dir"
done

# --- Stack starten ---
echo "Starte NAS-Stack..."
cd "$NAS_DIR"
docker compose pull
docker compose up -d

# --- Status ---
echo ""
echo "=== Container-Status ==="
docker compose ps

echo ""
echo "=== Phase 4 abgeschlossen ==="
echo ""
echo "Nächste Schritte:"
echo "  1. Cloudflare Tunnel Subdomains konfigurieren → siehe 05-cloudflare-subdomains.sh"
echo "  2. Filebrowser: http://127.0.0.1:8080 (Standard: admin/admin → sofort ändern!)"
echo "  3. Vaultwarden: http://127.0.0.1:8280"
echo "  4. Jellyfin: http://127.0.0.1:8096"
echo "  5. Homepage: http://127.0.0.1:3000"
echo "  6. Uptime Kuma: http://127.0.0.1:3001"
echo "  7. Samba einrichten + Nutzer anlegen: sudo bash setup/06-samba-host.sh"
