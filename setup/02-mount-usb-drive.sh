#!/bin/bash
# =============================================================================
#  02 — USB-HDD/SSD mounten und fstab konfigurieren
#  Ausführen als root nach Phase 1
# =============================================================================
set -euo pipefail

echo "=== DietPi NAS Setup — Phase 2: USB-Laufwerk ==="

# --- Laufwerk identifizieren ---
echo "Angeschlossene Laufwerke:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
echo ""

# Typischerweise: USB-Laufwerk /dev/sda1 oder NVMe-SSD /dev/nvme0n1p1
read -p "Partition (z.B. /dev/sda1 oder /dev/nvme0n1p1): " USB_PART
read -p "Dateisystem (ext4/ntfs/exfat) [ext4]: " FS_TYPE
FS_TYPE=${FS_TYPE:-ext4}

# --- Mountpoint erstellen ---
MOUNT_POINT="/mnt/data"
mkdir -p "$MOUNT_POINT"

# --- Nur ext4: Nutzerrechte + Quotas brauchen ein Linux-Dateisystem ---
# NTFS/exFAT kennen keine Linux-Rechte und keine Quotas. NTFS läuft auf dem
# Pi außerdem über FUSE (ntfs-3g) und ist deutlich langsamer.
if [[ "$FS_TYPE" != "ext4" ]]; then
    echo "FEHLER: Für Nutzerverwaltung + Speicherlimits ist ext4 Pflicht."
    echo "        Daten vorher sichern und das Laufwerk als ext4 formatieren."
    exit 1
fi

apt-get install -y quota e2fsprogs >/dev/null

# --- Formatieren (optional) ---
read -p "Laufwerk als ext4 formatieren? (j/n): " FORMAT
if [[ "$FORMAT" == "j" ]]; then
    echo "ACHTUNG: Alle Daten auf $USB_PART werden gelöscht!"
    read -p "Wirklich formatieren? (JA zum Bestätigen): " CONFIRM
    if [[ "$CONFIRM" == "JA" ]]; then
        umount "$USB_PART" 2>/dev/null || true
        # -O quota: Quota-Feature direkt im Dateisystem (keine aquota-Dateien)
        # -m 1:     nur 1 % für root reservieren statt 5 % (bei 4 TB = 160 GB gespart)
        mkfs.ext4 -L nasdata -m 1 -O quota -E quotatype=usrquota "$USB_PART"
    else
        echo "Formatierung abgebrochen."; exit 1
    fi
else
    # Vorhandenes ext4: Quota-Feature nachrüsten (geht nur ungemountet)
    if ! dumpe2fs -h "$USB_PART" 2>/dev/null | grep -q "^Filesystem features:.*quota"; then
        echo "Rüste Quota-Feature auf vorhandenem ext4 nach ..."
        umount "$USB_PART" 2>/dev/null || true
        e2fsck -f -y "$USB_PART"
        tune2fs -O quota -Q usrquota "$USB_PART"
    fi
fi

# --- Mounten ---
# usrquota schaltet die Durchsetzung der Limits ein
MOUNT_OPTS="defaults,noatime,lazytime,commit=60,usrquota,errors=remount-ro"
mount -o "$MOUNT_OPTS" "$USB_PART" "$MOUNT_POINT"

# --- fstab-Eintrag (idempotent) ---
UUID=$(blkid -s UUID -o value "$USB_PART")
if grep -q "$UUID" /etc/fstab; then
    echo "fstab-Eintrag für UUID=$UUID existiert bereits – prüfe, ob 'usrquota' enthalten ist!"
    grep "$UUID" /etc/fstab
else
    # nofail: Pi bootet auch, wenn die Platte mal nicht angeschlossen ist
    echo "UUID=$UUID  $MOUNT_POINT  ext4  $MOUNT_OPTS,nofail,x-systemd.device-timeout=30  0  2" >> /etc/fstab
    echo "fstab-Eintrag hinzugefügt."
fi

quotaon -u "$MOUNT_POINT" 2>/dev/null || true
quotaon -pu "$MOUNT_POINT"

# --- I/O-Scheduler setzen ---
DISK_PARENT=$(lsblk -no PKNAME "$USB_PART" 2>/dev/null || true)
if [ -n "$DISK_PARENT" ]; then
    DISK_NAME=$(basename "$DISK_PARENT")
else
    DISK_NAME=$(basename "$(echo "$USB_PART" | sed -E 's/p?[0-9]+$//')")
fi
# SSD → mq-deadline, HDD → bfq
read -p "SSD oder HDD? (ssd/hdd) [hdd]: " DISK_TYPE
DISK_TYPE=${DISK_TYPE:-hdd}

if [[ "$DISK_TYPE" == "ssd" ]]; then
    SCHEDULER="mq-deadline"
else
    SCHEDULER="bfq"
fi

echo "$SCHEDULER" > "/sys/block/$DISK_NAME/queue/scheduler"
# Persistenz via udev-Regel:
cat > /etc/udev/rules.d/60-ioscheduler.rules << EOF
# NAS USB-Laufwerk: I/O-Scheduler
ACTION=="add|change", KERNEL=="$DISK_NAME", ATTR{queue/scheduler}="$SCHEDULER"
EOF

# --- Verzeichnisstruktur anlegen ---
# Die Freigabe-Ordner (shares/users, gemeinsam, media, backups) samt Rechten
# legt 06-samba-host.sh an.
mkdir -p "$MOUNT_POINT"/shares
mkdir -p "$MOUNT_POINT"/docker-volumes/{filebrowser,nextcloud-data,vaultwarden,jellyfin/{config,cache},homepage,uptime-kuma}

echo ""
echo "=== Phase 2 abgeschlossen ==="
echo "Gemountet: $USB_PART → $MOUNT_POINT ($FS_TYPE)"
echo "I/O-Scheduler: $SCHEDULER"
echo "Verzeichnisse angelegt."
echo ""
echo "Nächster Schritt: sudo bash 03-docker-data-root.sh"
