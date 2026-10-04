# Sicherheits-Audit & Hardening Report — Raspberry Pi 5 NAS

Dieser Bericht dokumentiert die Sicherheitsarchitektur, den aktuellen Audit-Status und konkrete Handlungsempfehlungen für das NAS-System.

---

## 1. Gesamtbewertung & Sicherheitsniveau

* **Gesamturteil:** 🟢 **Exzellent / Enterprise-Niveau für den Heimgebrauch**
* **Angriffsfläche aus dem Internet (WAN):** **Minimal (nahezu 0)**. Keine offenen Ports am Router, keine IP-Exponierung.
* **Architektur:** Strikte Zero-Trust- und Defense-in-Depth-Prinzipien (Mehrschichtige Absicherung).

---

## 2. Audit der 5 Sicherheitszonen

### Zone 1: Internet & Perimeter (Cloudflare Zero Trust Tunnel)
* [x] **Kein Port-Forwarding:** Im Router sind keine Portweiterleitungen (z.B. 80, 443, 22, 445) eingerichtet. Portscanner (Shodan, Censys) finden das NAS nicht.
* [x] **Ausgehender Tunnel (Outbound Only):** Der `cloudflared`-Container baut ausschließlich ausgehende Verbindungen zu den Cloudflare-Rechenzentren auf. Eingehender Datenverkehr wird serverseitig von Cloudflare geprüft.
* [x] **DDoS- & Bot-Schutz:** Cloudflare filtert Denial-of-Service-Angriffe und bekannte bösartige Scanner ab, bevor Anfragen das heimische Netz erreichen.
* [x] **SSL/TLS-Verschlüsselung:** Alle Verbindungen sind automatisch mit validen HTTPS-Zertifikaten abgesichert.

### Zone 2: Identitätsschutz & Admin-Absicherung (Cloudflare Access)
* [x] **Zero Trust Vorschaltseite:** Die administrativen Oberflächen (`files.nas-clemens.de`, `home.nas-clemens.de`, `status.nas-clemens.de`) sind hinter Cloudflare Access geschützt.
* [x] **E-Mail-OTP (One-Time-PIN):** Angreifer können die Login-Masken von Filebrowser, Homepage oder Uptime Kuma gar nicht erst aufrufen, ohne zuvor einen PIN-Code an deine private E-Mail-Adresse zu erhalten.
* [x] **Direktzugänge abgekapselt:** Dienste wie Vaultwarden und Nextcloud besitzen starke interne Kryptographie und eigene Login-Barrieren.

### Zone 3: Container-Isolation & Docker-Härtung
* [x] **Localhost-Binding (`127.0.0.1`):** Alle Web-Container binden ihre Ports ausschließlich auf `127.0.0.1`. Sie sind selbst im lokalen WLAN/LAN **nicht** direkt über die IP des Pi erreichbar. Dies verhindert "Lateral Movement" (Angriffe durch ein kompromittiertes Gerät im Heimnetz).
* [x] **Capability Drops (`cap_drop: [ALL]`):** Containern (`cloudflared`, `vaultwarden`, `filebrowser`, `homepage`) wurden alle überflüssigen Linux-Root-Berechtigungen entzogen.
* [x] **No-New-Privileges:** `security_opt: [no-new-privileges:true]` verhindert, dass Prozesse im Container höhere Berechtigungen anfordern können.
* [x] **Unveränderliches Root-Dateisystem (`read_only: true`):** Malware kann sich nicht in Systemordnern von `cloudflared`, `filebrowser`, `vaultwarden` und `homepage` einnisten. Temporäre Daten landen in flüchtigen RAM-Disks (`tmpfs`).
* [x] **PID-Limits (`pids_limit`):** Verhindert Fork-Bomben und Ressourcen-Erschöpfung des Raspberry Pi.

### Zone 4: Lokale Dateifreigaben (Samba) & Speicherlimits
* [x] **Strikte LAN-Bindung:** Samba lauscht nur auf dem internen Subnetz `192.168.0.0/24`. Der SMB-Port `445` ist unter keinen Umständen über das Internet erreichbar.
* [x] **Getrennte Benutzerrechte:** Private Benutzerordner haben restriktive Zugriffsrechte (`0700` bzw. `0750`). Kein Benutzer kann die Daten anderer einsehen.
* [x] **Kernel-Quotas (ext4):** Unumgehbare Speicherlimits verhindern "Denial-of-Storage"-Zustände, bei denen ein Nutzer die gesamte 3,6 TB Festplatte füllt und Systemdienste lahmlegt.

### Zone 5: Host-System & Betriebssystem (DietPi)
* [x] **Minimale Angriffsfläche:** DietPi verzichtet auf unnötige Hintergrunddienste, GUI-Desktop und überflüssige Webserver.
* [x] **SSH-Absicherung:** SSH läuft über Public-Key-Authentifizierung. 

---

## 3. Sicherheits-Checkliste für den Betreiber (To-Do)

Um das Maximum an Sicherheit im Alltag zu garantieren, befolge diese 4 Empfehlungen:

| Maßnahme | Warum? | Wo einstellen? |
|---|---|---|
| **1. Vaultwarden Registrierung schließen** | Verhindert, dass fremde Personen Konten in deinem Passworttresor erstellen. | In `/root/nas/.env`: `VAULTWARDEN_SIGNUPS=false`, danach `docker compose up -d vaultwarden`. |
| **2. Nextcloud 2FA aktivieren** | Schützt deine Cloud-Dateien selbst bei kompromittiertem Passwort. | In Nextcloud: *Profil → Einstellungen → Sicherheit → Zwei-Faktor-Authentifizierung (TOTP)*. |
| **3. Filebrowser Admin-Passwort ändern** | Das Standard-Passwort ist `admin`. | Nach erstem Login in `files.nas-clemens.de`: *Settings → User Management → admin bearbeiten*. |
| **4. Externe Backups (3-2-1-Regel)** | Schützt vor physischem Diebstahl, Hardwaredefekt oder Brand. | Siehe [`backup-strategie.md`](file:///home/clemi/Projekte/NAS/docs/backup-strategie.md). |

---

## 4. Sinnvolle Zusatzfunktionen für dein NAS

Dein Raspberry Pi 5 mit schnellem Quad-Core-Prozessor und reichlich RAM hat noch reichlich Reserven für weitere nützliche Dienste:

### 1. Paperless-ngx (Das papierlose Büro)
* **Was es tut:** Der Goldstandard für Dokumentenmanagement. Du scannst oder fotografierst Briefe, Rechnungen und Verträge. Paperless führt vollautomatisch OCR-Texterkennung durch, erkennt Absender/Beträge und macht alle Dokumente sekundenschnell im Volltext durchsuchbar.
* **Ressourcen:** Läuft auf dem Pi 5 hervorragend.

### 2. Pi-hole oder AdGuard Home (Netzwerkweiter Werbeblocker)
* **Was es tut:** Blockiert Werbung, Tracking und Malware-Domains für **alle** Geräte in deinem Heimnetzwerk (Smart-TVs, Handys, Tablets, PCs), ohne dass auf den Geräten Browser-Plugins installiert werden müssen.
* **Ressourcen:** Minimal (~30 MB RAM).

### 3. Tailscale (Sicherer Fernzugriff auf Samba & SSH)
* **Was es tut:** Erstellt ein verschlüsseltes WireGuard-Mesh-VPN zwischen deinen Geräten. Du kannst damit auch von unterwegs im Zug auf deine schnellen Samba-Freigaben (`smb://...`) oder die SSH-Konsole des Pi zugreifen, als wärst du zuhause im Wohnzimmer.

### 4. Audiobookshelf (Hörbücher & Podcasts)
* **Was es tut:** Wie ein privates "Audible". Verwaltet Hörbücher und Podcasts mit eleganter Weboberfläche, Kapitelerkennung, Fortschrittssynchronisation und erstklassigen Apps für Android und iOS.

### 5. Calibre-Web (Digitale E-Book-Bibliothek)
* **Was es tut:** Zentrale Verwaltung deiner E-Books (EPUB, PDF, MOBI). Ermöglicht direktes Lesen im Browser und drahtloses Senden von Büchern an Kindle, Tolino oder Kobo Reader.

### 6. Immich (High-End Fotoverwaltung)
* **Was es tut:** Falls dir Nextcloud-Fotos nicht modern genug ist: Immich ist ein vollwertiger Google-Photos-Klon mit KI-Gesichtserkennung, Objekterkennung, interaktiver Weltkarte und blitzschnellem App-Sync. Auf dem Pi 5 performt Immich sehr gut.
