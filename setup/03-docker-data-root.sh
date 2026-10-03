#!/bin/bash
# =============================================================================
#  03 — Docker data-root auf USB-Laufwerk umleiten
#  Damit Container-Images und -Daten auf der großen Platte statt
#  auf der kleinen microSD liegen.
# =============================================================================
set -euo pipefail

echo "=== DietPi NAS Setup — Phase 3: Docker data-root ==="

DATA_ROOT="/mnt/data"
DOCKER_ROOT="$DATA_ROOT/docker-engine"

# --- Prüfe ob USB gemountet ist ---
if ! mountpoint -q "$DATA_ROOT"; then
    echo "FEHLER: $DATA_ROOT ist nicht gemountet!"
    echo "Führe zuerst 02-mount-usb-drive.sh aus."
    exit 1
fi

# --- Docker stoppen ---
systemctl stop docker docker.socket

# --- Neues Verzeichnis anlegen ---
mkdir -p "$DOCKER_ROOT"

# --- daemon.json konfigurieren ---
DAEMON_JSON="/etc/docker/daemon.json"
if [ -f "$DAEMON_JSON" ]; then
    echo "Vorhandene $DAEMON_JSON wird gesichert → ${DAEMON_JSON}.bak"
    cp "$DAEMON_JSON" "${DAEMON_JSON}.bak"
fi

cat > "$DAEMON_JSON" << EOF
{
    "data-root": "$DOCKER_ROOT",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "default-address-pools": [
        {
            "base": "172.20.0.0/16",
            "size": 24
        }
    ]
}
EOF

# --- Alte Docker-Daten migrieren (falls vorhanden) ---
OLD_DOCKER="/var/lib/docker"
if [ -d "$OLD_DOCKER" ] && [ "$(ls -A $OLD_DOCKER 2>/dev/null)" ]; then
    echo "Migriere Docker-Daten von $OLD_DOCKER → $DOCKER_ROOT ..."
    rsync -aP "$OLD_DOCKER/" "$DOCKER_ROOT/"
    mv "$OLD_DOCKER" "${OLD_DOCKER}.old"
    echo "Alte Daten in ${OLD_DOCKER}.old (nach Verifizierung löschen)."
fi

# --- Docker starten ---
systemctl start docker

# --- Verifizieren ---
echo ""
echo "Docker data-root:"
docker info 2>/dev/null | grep "Docker Root Dir"
echo ""
echo "Speicherplatz:"
df -h "$DOCKER_ROOT"

echo ""
echo "=== Phase 3 abgeschlossen ==="
echo "Docker nutzt jetzt $DOCKER_ROOT auf dem USB-Laufwerk."
echo ""
echo "Nächster Schritt: sudo bash 04-deploy-stack.sh"
