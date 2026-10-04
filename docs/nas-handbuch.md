# Clemens NAS — Das Handbuch & Benutzeranleitung

Dieses Handbuch dokumentiert den laufenden Betrieb, die Nutzerverwaltung, den Zugriff auf alle Dienste sowie automatische Datensicherungen für dein Raspberry Pi 5 NAS.

---

## Inhaltsverzeichnis
1. [Übersicht aller Dienste & Subdomains](#1-übersicht-aller-dienste--subdomains)
2. [Wo und wie melde ich mich an? (Login-Guide)](#2-wo-und-wie-melde-ich-mich-an-login-guide)
3. [Nutzer anlegen & Speicherlimits verwalten](#3-nutzer-anlegen--speicherlimits-verwalten)
4. [Netzlaufwerk unter Ubuntu einbinden (Samba)](#4-netzlaufwerk-unter-ubuntu-einbinden-samba)
5. [Automatische Datensicherungen & Cloud-Sync](#5-automatische-datensicherungen--cloud-sync)
6. [Tipps, Apps & Wartung im Alltag](#6-tipps-apps--wartung-im-alltag)

---

## 1. Übersicht aller Dienste & Subdomains

Alle Webdienste sind über verschlüsselte **Cloudflare Tunnels** angebunden. Dein Router benötigt **keine Portweiterleitungen**.

| Subdomain | Funktion | Sicherheitsstufe (Cloudflare) |
|---|---|---|
| **`cloud.nas-clemens.de`** | **Nextcloud AIO**: Privater Cloudspeicher, Dateisync, Fotos, Kontakte, Kalender, Nextcloud Office (Collabora). | **Direktzugriff** (kein PIN nötig, damit Handy-Apps und Desktop-Sync synchronisieren können). |
| **`vault.nas-clemens.de`** | **Vaultwarden**: Privater Bitwarden-Passworttresor mit Ende-zu-Ende-Verschlüsselung. | **Direktzugriff** (Apps und Browser-Addons synchronisieren direkt). |
| **`files.nas-clemens.de`** | **Filebrowser**: Web-Dateimanager für Admins (voller Durchgriff auf alle Platten-Shares). | 🔒 **Cloudflare Access** (Vorab-E-Mail-PIN-Abfrage). |
| **`media.nas-clemens.de`** | **Jellyfin**: Heimkino & Medienserver (Filme, Serien, Musik, Fotos). | **Direktzugriff** (für Smart-TVs & Apps). |
| **`home.nas-clemens.de`** | **Homepage**: Dashboard-Übersicht aller Dienste, Ping-Zeiten und Systemstatus. | 🔒 **Cloudflare Access** (Vorab-E-Mail-PIN-Abfrage). |
| **`status.nas-clemens.de`** | **Uptime Kuma**: Monitoring, Verfügbarkeitsprüfungen und Alarmierung bei Ausfällen. | 🔒 **Cloudflare Access** (Vorab-E-Mail-PIN-Abfrage). |
| *Lokales Netzwerk (keine Domain)* | **Samba / SMB**: Schneller Dateizugriff mit voller Gigabit-LAN-Geschwindigkeit (`~110 MB/s`). | 🔒 **Nur LAN / VPN** (kein Zugriff aus dem Internet). |

---

## 2. Wo und wie melde ich mich an? (Login-Guide)

### A. Nextcloud (`cloud.nas-clemens.de`)
* **Wie loggst du dich ein?** Mit dem Benutzer und Passwort, das du mit dem Skript `nas-user.sh` angelegt hast (z.B. `clemi`).
* **Ersteinrichtung:** Der initiale Haupt-Admin wird beim ersten Start von Nextcloud AIO im Setup-Dashboard angezeigt.

### B. Vaultwarden (`vault.nas-clemens.de`)
* **Wie loggst du dich ein?** Auf der Startseite auf **"Konto erstellen"** klicken. Vergib deine E-Mail-Adresse und ein sehr starkes **Master-Passwort**. 
* **Wichtig:** Da die Tresore Ende-zu-Ende verschlüsselt sind, kann niemand (auch kein Admin) dein Passwort zurücksetzen!
* **Admin-Panel:** Unter `https://vault.nas-clemens.de/admin` erreichst du die Admin-Konsole. Das Passwort hierfür ist der `VAULTWARDEN_ADMIN_TOKEN` aus deiner `/root/nas/.env`.

### C. Filebrowser (`files.nas-clemens.de`)
* **Schritt 1:** E-Mail-PIN von Cloudflare eingeben.
* **Schritt 2:** Initial-Login mit Benutzername `admin` und Passwort `admin`.
* **Wichtig:** Nach dem ersten Login sofort rechts oben auf *Einstellungen (Settings) → Benutzer bearbeiten* gehen und ein neues, sicheres Passwort vergeben!

### D. Uptime Kuma (`status.nas-clemens.de`)
* **Schritt 1:** E-Mail-PIN von Cloudflare eingeben.
* **Schritt 2:** Beim ersten Aufruf fordert dich das System auf, ein neues Admin-Konto anzulegen.

### E. Jellyfin (`media.nas-clemens.de`)
* Beim ersten Aufruf leitet dich der Assistent durch die Erstellung deines Benutzerkontos und fragt nach den Medienordnern (liegen unter `/media`).

---

## 3. Nutzer anlegen & Speicherlimits verwalten

Für Personen, die Speicherplatz auf deinem NAS bekommen sollen (du selbst, Familie, Freunde), gibt es das zentrale Skript [`scripts/nas-user.sh`](file:///home/clemi/Projekte/NAS/scripts/nas-user.sh).

Ein einziger Befehl synchronisiert:
1. Den **Linux- & Samba-Nutzer** (Zugriff per Netzlaufwerk mit unumgehbarem ext4-Kernel-Limit).
2. Den **Nextcloud-Nutzer** (Zugriff per Cloud mit Nextcloud-Limit).

### Befehle auf dem Pi (als root in `/root/nas`)

```bash
# 1. Admin-Nutzer anlegen (ohne Limit)
bash scripts/nas-user.sh add clemi --smb none --cloud none --admin

# 2. Normalen Nutzer mit Limits anlegen (z.B. 100 GB Platte, 20 GB Cloud)
bash scripts/nas-user.sh add anna --smb 100G --cloud 20G

# 3. Nur Cloud-Nutzer ohne Samba-Netzlaufwerk
bash scripts/nas-user.sh add papa --no-smb --cloud 50G

# 4. Speicherlimit im laufenden Betrieb anpassen
bash scripts/nas-user.sh quota anna --smb 200G
bash scripts/nas-user.sh quota anna --cloud 50G

# 5. Passwort eines Nutzers ändern (ändert Samba + Nextcloud gleichzeitig)
bash scripts/nas-user.sh passwd anna

# 6. Alle Nutzer und ihren belegten Speicher auflisten
bash scripts/nas-user.sh list

# 7. Nutzer löschen (verschiebt privaten Ordner zur Sicherheit ins Backup-Archiv)
bash scripts/nas-user.sh del anna

# 8. Nutzer endgültig löschen (inklusive Datenvernichtung)
bash scripts/nas-user.sh del anna --purge
```

---

## 4. Netzlaufwerk unter Ubuntu einbinden (Samba)

### Grafisch im Dateimanager (Nautilus)
1. Öffne die App **Dateien**.
2. Drücke die Tastenkombination **Strg + L** (die Adressleiste wird editierbar).
3. Gib ein:
   ```text
   smb://192.168.0.53
   ```
4. Drücke **Enter**.
5. Wähle **"Registrierter Benutzer"**, gib deinen Benutzernamen (z.B. `clemi`) und dein Passwort ein und hake *"Passwort nie vergessen"* an.
6. **Lesezeichen setzen:** Klicke mit der rechten Maustaste auf den gemounteten Ordner in der linken Seitenleiste und wähle **"Zu Lesezeichen hinzufügen"**. Ab jetzt reicht ein Klick!

### Freigegebene Ordner
* `\\192.168.0.53\<benutzername>`: Dein persönlicher, privater Ordner (niemand sonst hat Zugriff).
* `\\192.168.0.53\gemeinsam`: Geteilter Ordner für alle registrierten Nutzer.
* `\\192.168.0.53\media`: Ordner für Filme, Musik und Fotos (wird von Jellyfin ausgelesen).
* `\\192.168.0.53\backups`: Dedizierter Sicherungsordner (nur für Admins beschreibbar).

---

## 5. Automatische Datensicherungen & Cloud-Sync

### A. Automatische Handy-Fotosicherung (Smartphone → NAS)
Nie wieder Google Fotos oder iCloud Speicher voll:
1. Installiere die offizielle **Nextcloud App** (Google Play Store oder Apple App Store).
2. Serveradresse eingeben: `https://cloud.nas-clemens.de`.
3. Mit deinem Benutzernamen und Passwort anmelden.
4. In der App auf **Einstellungen → Automatischer Upload** gehen.
5. Kamera-Ordner auswählen und aktivieren.
6. *Empfohlene Option:* *"Nur bei WLAN hochladen"* und *"Nur während des Ladens hochladen"* aktivieren.
7. Alle neuen Fotos werden ab sofort automatisch im Hintergrund auf dein heimisches 3,6 TB NAS geladen.

### B. Ubuntu PC-Ordner automatisch synchronisieren (PC ↔ NAS)
Damit deine Dokumente auf dem PC immer gesichert und auf dem Laptop verfügbar sind:
1. Installiere den Nextcloud-Client auf Ubuntu:
   ```bash
   sudo apt install nextcloud-client
   ```
2. Starte die Nextcloud-App, trage `https://cloud.nas-clemens.de` ein.
3. Wähle aus, welche lokalen Ordner (z.B. `~/Dokumente` oder `~/Projekte`) automatisch im Hintergrund mit dem NAS synchronisiert werden sollen.

### C. Sicherung des gesamten NAS (Nextcloud AIO BorgBackup)
Nextcloud AIO hat ein extrem mächtiges, integriertes Backup-System basierend auf **BorgBackup** (verschlüsselt, dedupliziert, inkrementell):
1. Öffne das AIO-Dashboard über den SSH-Tunnel:
   ```bash
   ssh -L 8180:127.0.0.1:8180 root@192.168.0.53
   # Im Browser öffnen: https://localhost:8180
   ```
2. Im Bereich **Backup and restore** kannst du einen Pfad angeben (z.B. eine zweite externe USB-Platte oder einen Netzwerkpfad).
3. Du vergibst ein Backup-Passwort und aktivierst den **täglichen automatischen Backup-Plan**.
4. AIO stoppt nachts kurz die Container, sichert die Datenbank sowie alle Dateien konsistent und startet die Container danach wieder.

---

## 6. Tipps, Apps & Wartung im Alltag

### Bitwarden Passwort-Manager im Browser & Handy
* Installiere die **Bitwarden** Erweiterung in Firefox / Chrome / Brave bzw. die Bitwarden-App auf deinem Smartphone.
* **Wichtig vor dem Login:** Klicke im Login-Fenster auf das **Zahnrad (Servereinstellungen)** und trage als Server-URL ein:
  ```text
  https://vault.nas-clemens.de
  ```
* Melde dich mit deinem Master-Konto an. Deine Passwörter synchronisieren sich verschlüsselt und blitzschnell.

### Automatische Updates (Watchtower)
Watchtower läuft im Hintergrund und aktualisiert nachts um 04:00 Uhr automatisch die Container, sobald Updates vorliegen. Über den konfigurierten Telegram-Bot wirst du auf dem Smartphone benachrichtigt.

### System-Updates für den Raspberry Pi
Führe alle paar Wochen ein Update des Host-Betriebssystems durch:
```bash
ssh root@192.168.0.53
dietpi-update
apt update && apt upgrade -y
```
