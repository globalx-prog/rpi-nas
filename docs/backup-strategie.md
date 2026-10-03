# Backup-Strategie für das Raspberry Pi NAS

## Grundprinzip

```text
Was wird gesichert?                     Wohin?
─────────────────────────────────────────────────────
1. Docker-Volumes (Konfigurationen)     → USB-Platte /mnt/data/backups/
2. Compose-Dateien + Configs            → USB-Platte /mnt/data/backups/
3. Shares (Dokumente, Medien)           → Externe Platte / Cloud (manuell)
```

> [!IMPORTANT]
> Backups auf dieselbe Platte wie die Daten sind **kein echtes Backup** —
> bei Plattenausfall sind beides weg. Für kritische Daten (Vaultwarden-DB!)
> ein Off-Site-Backup einrichten (Nextcloud → externen Speicher, rsync auf
> zweite Platte, oder Duplicati → Cloud).

## Automatisches Backup-Skript

```bash
#!/bin/bash
# /usr/local/bin/backup-nas-stack.sh
set -euo pipefail

BACKUP_DIR="/mnt/data/backups/nas-stack"
DATE=$(date +%Y%m%d_%H%M)
TARGET="$BACKUP_DIR/$DATE"
RETENTION_DAYS=14

mkdir -p "$TARGET"

echo "[$DATE] NAS Backup gestartet..."

# 1. Docker-Volumes (komprimiert)
for vol in filebrowser vaultwarden jellyfin/config homepage uptime-kuma; do
    vol_name=$(echo "$vol" | tr '/' '-')
    tar czf "$TARGET/vol-${vol_name}.tar.gz" \
        -C /mnt/data/docker-volumes "$vol" 2>/dev/null || true
done

# 2. Compose + Configs
tar czf "$TARGET/nas-configs.tar.gz" \
    -C /home/dietpi nas/docker-compose.yml \
    nas/configs/ \
    nas/.env 2>/dev/null || true

# 3. Vaultwarden-DB separat (besonders kritisch)
if [ -f /mnt/data/docker-volumes/vaultwarden/db.sqlite3 ]; then
    sqlite3 /mnt/data/docker-volumes/vaultwarden/db.sqlite3 ".backup '$TARGET/vaultwarden-db.sqlite3'"
    echo "  Vaultwarden-DB: Hot-Backup erstellt"
fi

# 4. Alte Backups löschen (Retention)
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "[$DATE] Backup abgeschlossen → $TARGET"
ls -lh "$TARGET"
```

## Cron einrichten

```bash
# Täglich um 03:00:
sudo crontab -e
# Eintrag:
0 3 * * * /usr/local/bin/backup-nas-stack.sh >> /var/log/nas-backup.log 2>&1
```

## Off-Site-Backup Optionen

| Methode | Aufwand | Kosten | Sicherheit |
|---|---|---|---|
| Zweite USB-Platte + rsync | Niedrig | ~50€ einmalig | Gut (physisch getrennt) |
| Nextcloud → WebDAV-Export | Mittel | Frei (eigene Instanz) | Mittel |
| Duplicati → Backblaze B2 | Mittel | ~1€/Monat pro 10 GB | Sehr gut (verschlüsselt, off-site) |
| rclone → Google Drive | Niedrig | 15 GB frei | Gut |

## Was wird NICHT gesichert

- **Docker-Images:** Können jederzeit per `docker compose pull` neu geladen werden.
- **Jellyfin-Cache:** Wird automatisch neu aufgebaut.
- **Media-Dateien in `/shares/media`:** Zu groß für automatisches Backup.
  → Manuell auf externe Platte kopieren oder per Nextcloud synchronisieren.
