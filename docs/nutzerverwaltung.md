# Nutzerverwaltung & Speicherlimits

## Konzept

Jeder Nutzer bekommt **zwei Speicherbereiche mit eigenem Limit**, beide mit demselben Login:

```text
                         nas-user.sh add anna --smb 100G --cloud 20G
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              ▼                                                   ▼
   SAMBA (LAN / Tailscale)                             NEXTCLOUD (überall)
   \\<pi-ip>\anna                                      https://cloud.nas-clemens.de
   ~110 MB/s im Gigabit-LAN                            Web, Handy-App, Desktop-Sync
   Limit: ext4-Kernel-Quota (100G)                     Limit: Nextcloud-Quota (20G)
   Ordner: /mnt/data/shares/users/anna                 Ordner: .../nextcloud-data/anna
```

| | Samba | Nextcloud |
|---|---|---|
| Wofür | Große Dateien, schnell im Heimnetz | Zugriff von unterwegs, Handy-Fotos, Sync, Teilen per Link |
| Limit durchgesetzt von | Linux-Kernel (unumgehbar) | Nextcloud |
| Was passiert bei vollem Limit | "Datenträger voll" im Explorer/Finder | Upload wird abgelehnt, Warnung in der App |
| Windows/macOS zeigt | Das Limit als Laufwerksgröße | – |

> [!NOTE]
> Die beiden Limits sind **getrennte Töpfe**: `--smb 100G --cloud 20G` heißt bis zu 120 GB insgesamt.
> Wer nur einen Bereich braucht: `--no-smb` oder `--no-cloud`.

### Warum zwei Systeme und nicht eins?

- **Nur Nextcloud:** wäre einfacher, aber WebDAV/HTTP auf dem Pi ist spürbar langsamer als SMB, und Nextcloud-Dateien gehören intern alle dem User `www-data`, sodass der Kernel kein Limit pro Person durchsetzen kann.
- **Nur Samba:** schnell, aber nicht sicher über das Internet erreichbar, und es gibt keine Apps.
- **Gemeinsame Anmeldung (LDAP, z. B. lldap):** möglich, aber Samba mit LDAP ist aufwendig. `nas-user.sh` hält die Passwörter stattdessen synchron. Später nachrüstbar, wenn es mehr als etwa 10 Nutzer werden.

---

## Befehle

Das Skript liegt unter [`scripts/nas-user.sh`](file:///home/clemi/Projekte/NAS/scripts/nas-user.sh) und läuft auf dem Pi als root.

```bash
cd /root/nas
chmod +x scripts/nas-user.sh

# Dich selbst als Admin, ohne Limit
./scripts/nas-user.sh add clemi --smb none --cloud none --admin

# Nutzer mit Limits
./scripts/nas-user.sh add anna  --smb 100G --cloud 20G
./scripts/nas-user.sh add papa  --no-smb --cloud 50G      # nur Cloud

# Limit ändern (sofort wirksam, kein Neustart)
./scripts/nas-user.sh quota anna --smb 200G
./scripts/nas-user.sh quota anna --cloud 50G

# Passwort ändern (Samba + Nextcloud gleichzeitig)
./scripts/nas-user.sh passwd anna

# Übersicht
./scripts/nas-user.sh list
#  NUTZER           ADMIN    SMB BELEGT    SMB LIMIT   CLOUD LIMIT
#  ──────────────────────────────────────────────────────────────────────
#  clemi            ja            1.2T   unbegrenzt   none
#  anna             -              37G         100G   20 GB

# Löschen: privater Samba-Ordner wird nach backups/geloeschte-nutzer/ verschoben
./scripts/nas-user.sh del anna
# ... oder endgültig:
./scripts/nas-user.sh del anna --purge
```

> [!WARNING]
> `del` löscht das Nextcloud-Konto **mit allen Cloud-Dateien**. Nur der Samba-Ordner wird archiviert.

Grafisch geht es in Nextcloud genauso: **Profilbild → Konten** zeigt alle Nutzer, die Spalte *Quota* ist direkt änderbar. Dort angelegte Nutzer haben aber **kein** Samba-Konto.

---

## Freigaben & Rechte

| Freigabe | Pfad auf `/mnt/data/shares/` | Wer liest | Wer schreibt | Zählt gegen |
|---|---|---|---|---|
| `\\pi\<name>` | `users/<name>/` | nur der Nutzer | nur der Nutzer | eigene Quota |
| `\\pi\gemeinsam` | `gemeinsam/` | alle Nutzer | alle Nutzer | Quota des Erstellers |
| `\\pi\media` | `media/` | alle Nutzer + Jellyfin | Admins | Quota des Admins |
| `\\pi\backups` | `backups/` | Admins | Admins | Quota des Admins |

Einbinden:
- **Windows:** Explorer → *Dieser PC* → *Netzlaufwerk verbinden* → `\\192.168.0.X\anna`
- **macOS:** Finder → `⌘K` → `smb://192.168.0.X/anna`
- **Linux:** Dateimanager → `smb://192.168.0.X/anna`
- **Unterwegs:** dasselbe über die Tailscale-IP des Pi (ist in `hosts allow` freigegeben)

---

## Gesamtgröße der Cloud begrenzen (optional)

Alle Nextcloud-Dateien gehören auf der Platte dem User `www-data` (UID 33). Mit einem Kernel-Limit auf diese UID kann die Cloud *insgesamt* nie mehr als z. B. 500 GB belegen. Dann bleibt für Samba garantiert genug Platz:

```bash
setquota -u 33 0 $((500*1024*1024)) 0 0 /mnt/data    # 500 GB
repquota -us /mnt/data                                # Kontrolle
```

## Speicherplanung (Beispiel 4-TB-Platte)

| Bereich | Größe |
|---|---|
| clemi (Admin, Medien, Backups) | unbegrenzt |
| 4 Nutzer × 200 GB Samba | 800 GB |
| 4 Nutzer × 50 GB Cloud | 200 GB |
| Docker, Nextcloud-DB, Jellyfin-Cache | ~50 GB |

Quotas dürfen in Summe größer sein als die Platte (Überbuchung), denn selten nutzt jeder sein Limit aus. `nas-user.sh list` zeigt am Ende die tatsächliche Belegung.

## Fehlersuche

| Problem | Prüfen |
|---|---|
| Limit greift nicht | `quotaon -pu /mnt/data` muss "is on" melden; in `/etc/fstab` muss `usrquota` stehen |
| Anmeldung an Samba schlägt fehl | `pdbedit -L` (ist der Nutzer drin?), `journalctl -u smbd`, eigene IP in `hosts allow`? |
| Cloud-Teil übersprungen | Nextcloud muss eingerichtet sein (`docker ps \| grep nextcloud-aio-nextcloud`), danach `add <name> --no-smb` |
| Nextcloud lehnt Passwort ab | Die Nextcloud-Passwortrichtlinie verlangt starke Passwörter; ein längeres wählen |
