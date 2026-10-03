#!/bin/bash
# =============================================================================
#  01 — DietPi Erst-Setup für NAS
#  Ausführen nach erstem SSH-Login auf dem Pi (als root)
# =============================================================================
set -euo pipefail

echo "=== DietPi NAS Setup — Phase 1: System-Grundlagen ==="

# --- System aktualisieren ---
apt-get update && apt-get upgrade -y

# --- Docker & Docker Compose installieren (DietPi oder Standard Raspberry Pi OS / Debian) ---
if [ -f /boot/dietpi/dietpi-software ]; then
    echo "DietPi erkannt: Installiere Docker über dietpi-software..."
    export PATH="$PATH:/boot/dietpi"
    /boot/dietpi/dietpi-software install 162 134
elif command -v dietpi-software >/dev/null 2>&1; then
    echo "DietPi erkannt: Installiere Docker über dietpi-software..."
    dietpi-software install 162 134
else
    echo "Standard Debian / Raspberry Pi OS erkannt: Installiere Docker & Compose..."
    apt-get install -y curl ca-certificates gnupg
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    apt-get install -y docker-compose-plugin
    systemctl enable --now docker
fi

# --- Kernel-Parameter für NAS-Performance ---
cat > /etc/sysctl.d/99-nas-performance.conf << 'EOF'
# --- Netzwerk-Performance ---
# TCP-Buffer vergrößern (Standard ist zu klein für Gigabit)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# --- Disk-I/O ---
# Mehr RAM für Schreib-Cache nutzen (gut für große Datei-Transfers)
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 3000

# --- Swap minimieren (nur Notfall-Swap) ---
vm.swappiness = 10

# --- Dateisystem-Cache ---
vm.vfs_cache_pressure = 50
EOF

sysctl --system

# --- I/O-Scheduler setzen (wird in 02 für das USB-Laufwerk spezifisch gesetzt) ---
echo "I/O-Scheduler wird in 02-mount-usb-drive.sh gesetzt."

# --- Lokale Firewall (iptables-basiert, DietPi-Default) ---
# Port 445 (Samba) nur im LAN erlauben, SSH nur von bekannten Quellen
echo "Firewall-Regeln werden nach dem vollständigen Setup konfiguriert."

# --- Tailscale installieren (optional, für privaten Zugriff) ---
read -p "Tailscale installieren? (j/n): " INSTALL_TS
if [[ "$INSTALL_TS" == "j" ]]; then
    curl -fsSL https://tailscale.com/install.sh | sh
    tailscale up
    echo "Tailscale aktiv: $(tailscale ip -4)"
fi

echo ""
echo "=== Phase 1 abgeschlossen ==="
echo "Nächster Schritt: sudo bash 02-mount-usb-drive.sh"
