#!/bin/bash
# =============================================================================
#  06 — Samba nativ auf dem Host + Gruppen + Freigabe-Ordner
#
#  Warum nicht im Container?  Speicherlimits pro Nutzer funktionieren über
#  ext4-Kernel-Quotas, und die hängen an echten Linux-UIDs. Samba braucht
#  ohnehin Host-Netzwerk und viele Capabilities, ein Container brächte also
#  kaum Isolation, dafür aber viel Komplexität bei der Nutzerverwaltung.
#  Die Absicherung läuft stattdessen über smb.conf (hosts allow, SMB3,
#  kein Gast) und eine systemd-Sandbox.
# =============================================================================
set -euo pipefail

NAS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_ROOT="/mnt/data"

echo "=== DietPi NAS Setup — Phase 6: Samba (Host) ==="

mountpoint -q "$DATA_ROOT" || { echo "FEHLER: $DATA_ROOT nicht gemountet."; exit 1; }

# --- Quota aktiv? (wird in 02 eingerichtet) ---
if ! quotaon -pu "$DATA_ROOT" 2>/dev/null | grep -q "is on"; then
    echo "WARNUNG: Benutzer-Quota auf $DATA_ROOT ist NICHT aktiv."
    echo "         Speicherlimits pro Nutzer greifen dann nicht. Siehe 02-mount-usb-drive.sh."
fi

# --- Alten Samba-Container entfernen (falls aus früherer Version vorhanden) ---
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx samba; then
    docker rm -f samba
    echo "Alter Samba-Container entfernt."
fi

# --- Pakete ---
apt-get update
apt-get install -y samba quota
# wsdd: Pi erscheint unter Windows in der "Netzwerk"-Ansicht (ohne NetBIOS/SMB1)
apt-get install -y wsdd 2>/dev/null || echo "wsdd nicht verfügbar – optional, übersprungen."

# --- Gruppen ---
getent group nas-users  >/dev/null || groupadd nas-users
getent group nas-admins >/dev/null || groupadd nas-admins

# --- Ordner + Rechte ---
#   users/      0711: man kann hineinwechseln, aber den Inhalt nicht auflisten
#   gemeinsam/  2775: alle nas-users schreiben, setgid hält die Gruppe
#   media/      2775: Gruppe nas-admins schreibt, alle lesen (auch Jellyfin)
#   backups/    2770: nur nas-admins
install -d -m 0711 -o root -g root        "$DATA_ROOT/shares/users"
install -d -m 2775 -o root -g nas-users   "$DATA_ROOT/shares/gemeinsam"
install -d -m 2775 -o root -g nas-admins  "$DATA_ROOT/shares/media"
install -d -m 2770 -o root -g nas-admins  "$DATA_ROOT/shares/backups"

# --- smb.conf ---
[ -f /etc/samba/smb.conf ] && cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M)"
install -m 0644 "$NAS_DIR/configs/samba/smb.conf" /etc/samba/smb.conf
testparm -s /etc/samba/smb.conf >/dev/null || { echo "FEHLER in smb.conf (testparm)"; exit 1; }

# --- systemd-Sandbox für smbd ---
mkdir -p /etc/systemd/system/smbd.service.d
cat > /etc/systemd/system/smbd.service.d/hardening.conf << 'EOF'
[Service]
ProtectSystem=full
PrivateTmp=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictRealtime=true
EOF

systemctl daemon-reload
systemctl disable --now nmbd 2>/dev/null || true   # NetBIOS nicht nötig
systemctl enable --now smbd
systemctl restart smbd
systemctl enable --now wsdd 2>/dev/null || true

echo ""
echo "=== Phase 6 abgeschlossen ==="
echo "Samba läuft:  $(systemctl is-active smbd)"
echo ""
echo "Ersten Nutzer (dich als Admin, unbegrenzt) anlegen:"
echo "  sudo $NAS_DIR/scripts/nas-user.sh add clemi --smb none --cloud none --admin"
echo ""
echo "Weitere Nutzer mit Limit:"
echo "  sudo $NAS_DIR/scripts/nas-user.sh add anna --smb 100G --cloud 20G"
