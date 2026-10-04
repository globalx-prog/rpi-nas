# Raspberry Pi 5 NAS — Gehärteter Docker-Stack mit Cloudflare Tunnel

> **Ziel:** Maximale Dateifreigabe-Performance auf einem Pi 5 (USB 3.0 HDD/SSD oder PCIe NVMe),
> alle Dienste als Docker-Container, extern erreichbar über Subdomains von `nas-clemens.de`.
>
> Basiert auf dem Härtungskonzept aus [`../LLM/ollama-zugriff/`](file:///home/clemi/Projekte/LLM/ollama-zugriff/README.md).

---

## Systemempfehlung

**DietPi (64-bit, ARM64)** — die richtige Wahl für maximale NAS-Performance:

| Kriterium | DietPi | Raspberry Pi OS Lite | OMV / CasaOS |
|---|---|---|---|
| RAM-Verbrauch (idle) | ~50 MB | ~150 MB | ~300–500 MB |
| Boot-Optimierung | Ja (dietpi-config) | Nein | Nein |
| Docker-Integration | `dietpi-software` #162 | Manuell | OMV: Plugin, CasaOS: integriert |
| Filesystem-Tweaks | Ja (ext4 lazytime, swappiness) | Nein | Teilweise |
| Overhead für NAS | Minimal — du steuerst alles | Mittel | Hoch (Web-UI frisst RAM) |

> **Warum nicht OMV/CasaOS?** Beide laufen als Web-UI-Prozesse und verbrauchen 200–400 MB RAM,
> die auf einem Pi 4B mit 4 GB für Docker-Container fehlen. Für reine Dateifreigabe + Docker
> ist DietPi schlanker, schneller und gibt dir volle Kontrolle. OMV/CasaOS eignen sich besser
> für Pi 5 (8 GB) oder wenn du eine GUI ohne SSH-Kenntnisse brauchst.

### Image flashen

1. [DietPi Image für RPi 4 (64-bit)](https://dietpi.com/#downloadinfo) herunterladen
2. Mit **Raspberry Pi Imager** oder **balenaEtcher** auf microSD flashen
3. Vor dem ersten Boot: `dietpi.txt` und `dietpi-wifi.txt` auf der Boot-Partition anpassen:
   - Hostname, WLAN-Daten, SSH-Key, Locale, Timezone

---

## Ist das ein Widerspruch? Image auf microSD + Daten auf Festplatte?

**Nein — das ist Best Practice.** Die Architektur:

```text
┌─────────────────────────────────────────────────────────────┐
│                    Raspberry Pi 4B                           │
│                                                             │
│  microSD (16–32 GB)              USB 3.0 HDD/SSD            │
│  ┌──────────────────┐            ┌────────────────────────┐ │
│  │ DietPi OS        │            │ /mnt/data              │ │
│  │ /boot, /         │            │ ├── shares/            │ │
│  │ Docker Engine     │            │ │   ├── documents/    │ │
│  │ Container-Images  │            │ │   ├── media/        │ │
│  │ Configs           │            │ │   └── backups/      │ │
│  └──────────────────┘            │ ├── docker-volumes/   │ │
│                                  │ │   ├── nextcloud/     │ │
│                                  │ │   ├── vaultwarden/   │ │
│                                  │ │   └── ...            │ │
│                                  └────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

- **microSD:** Nur das Betriebssystem, Docker Engine und Container-Images (~8–16 GB)
- **USB-HDD/SSD:** Alle Daten, Shares, Docker-Volumes → schneller I/O über USB 3.0 (~350 MB/s SSD, ~120 MB/s HDD)
- Docker's `data-root` wird auf die USB-Platte umgeleitet (siehe `setup/` Skripte)

> [!TIP]
> Für maximale Performance eine **USB 3.0 SSD** (z.B. Samsung T7) verwenden.
> Eine HDD reicht aber völlig für NAS-Zwecke (Streaming, Dateifreigabe).

---

## Architektur

```text
                      INTERNET / CLIENTS
                              │
               ┌──────────────┴──────────────┐
               ▼                             ▼
     Cloudflare Zero Trust            Tailscale Network
   (*.nas-clemens.de)               (100.x.y.z Tailnet)
               │                             │
        (QUIC Outbound)               (WireGuard VPN)
               ▼                             ▼
       cloudflared (Docker)          Raspberry Pi 4B (Host)
               │                             │
    ═══════════╪═════════════════════════════╪═════════════════
               │     Docker Network: nas-network             │
               ▼                                             │
   ┌───────────────────────────────────────────────────────┐ │
   │                     Services                          │ │
   │                                                       │ │
   │  ┌─────────┐  ┌───────────┐  ┌─────────────────────┐ │ │
   │  │ Samba   │  │ Filebrowser│  │  Nextcloud (AIO)    │ │ │
   │  │ :445    │  │ :8080      │  │  :11000 (HTTPS)     │ │ │
   │  └─────────┘  └───────────┘  └─────────────────────┘ │ │
   │                                                       │ │
   │  ┌─────────┐  ┌───────────┐  ┌─────────────────────┐ │ │
   │  │Vaultwar-│  │ Jellyfin  │  │  Heimdall / Homepage│ │ │
   │  │den :80  │  │ :8096     │  │  :3000               │ │ │
   │  └─────────┘  └───────────┘  └─────────────────────┘ │ │
   │                                                       │ │
   │  ┌─────────────────────────────────────────────────┐  │ │
   │  │  Watchtower (Auto-Update) + Uptime Kuma (Mon.)  │  │ │
   │  └─────────────────────────────────────────────────┘  │ │
   └───────────────────────────────────────────────────────┘ │
                                                             │
   USB 3.0: /mnt/data (HDD/SSD — alle Volumes + Shares)     │
═════════════════════════════════════════════════════════════
```

---

## Service-Übersicht & Subdomains

| Service | Funktion | Subdomain | Port (intern) | Priorität |
|---|---|---|---|---|
| **Samba** | SMB/CIFS Dateifreigabe (LAN, max. Speed) | — (nur LAN) | 445 | ⭐ Kern |
| **Filebrowser** | Web-basierter Dateimanager | `files.nas-clemens.de` | 8080 | ⭐ Kern |
| **cloudflared** | Cloudflare Tunnel Connector | — | — (nur outbound) | ⭐ Kern |
| **Nextcloud AIO** | Cloud-Speicher, Kalender, Kontakte | `cloud.nas-clemens.de` | 11000 | ⭐⭐ Empfohlen |
| **Vaultwarden** | Passwort-Manager (Bitwarden-kompatibel) | `vault.nas-clemens.de` | 80 | ⭐⭐ Empfohlen |
| **Jellyfin** | Medienserver (Streaming) | `media.nas-clemens.de` | 8096 | ⭐⭐ Empfohlen |
| **Homepage** | Dashboard für alle Services | `home.nas-clemens.de` | 3000 | 🔧 Optional |
| **Uptime Kuma** | Monitoring & Benachrichtigungen | `status.nas-clemens.de` | 3001 | 🔧 Optional |
| **Watchtower** | Auto-Update für Container | — | — | 🔧 Optional |
| **Pi-hole** | DNS-Werbeblocker | `dns.nas-clemens.de` | 8053/80 | 🔧 Optional |

> [!IMPORTANT]
> **Samba** läuft **nativ auf dem Host** (nicht in Docker) und ist nur im LAN und über Tailscale
> erreichbar. Das ist gewollt: SMB über das Internet zu tunneln wäre unsicher und langsam.
> Für Dateizugriff von unterwegs → Nextcloud über den Cloudflare Tunnel.

---

## Nutzerverwaltung mit Speicherlimits

Jeder Nutzer bekommt einen **privaten Samba-Ordner** (LAN, schnell) und ein **Nextcloud-Konto**
(überall), jeweils mit eigenem, jederzeit änderbarem Limit. Ein Befehl legt beides an:

```bash
sudo ./scripts/nas-user.sh add anna --smb 100G --cloud 20G
sudo ./scripts/nas-user.sh quota anna --smb 200G
sudo ./scripts/nas-user.sh list
```

Das Samba-Limit setzt der Linux-Kernel durch (ext4-Quota), das Cloud-Limit Nextcloud.
→ Details: [`docs/nutzerverwaltung.md`](file:///home/clemi/Projekte/NAS/docs/nutzerverwaltung.md)

---

## Verzeichnisstruktur (dieses Repository)

```text
NAS/
├── README.md                          # ← Diese Datei
├── docker-compose.yml                 # Container-Services (ohne Samba)
├── .env.example                       # Template für alle Konfigurationswerte
├── configs/
│   ├── samba/
│   │   └── smb.conf                   # Samba-Konfiguration (Host)
│   ├── filebrowser/
│   │   └── settings.json              # Filebrowser-Konfiguration
│   └── homepage/
│       ├── services.yaml              # Dashboard-Services
│       └── settings.yaml              # Dashboard-Settings
├── scripts/
│   └── nas-user.sh                    # Nutzer anlegen/ändern/löschen + Quotas
├── setup/
│   ├── 01-dietpi-initial-setup.sh     # Erst-Setup nach DietPi-Boot
│   ├── 02-mount-usb-drive.sh          # USB-Platte: ext4 + Quota + fstab
│   ├── 03-docker-data-root.sh         # Docker data-root auf USB umleiten
│   ├── 04-deploy-stack.sh             # Container-Stack starten
│   ├── 05-cloudflare-subdomains.sh    # Anleitung: Subdomains + Access
│   └── 06-samba-host.sh               # Samba nativ + Gruppen + Freigaben
└── docs/
    ├── nas-handbuch.md                # Vollständiges Handbuch & Bedienungsanleitung
    ├── nutzerverwaltung.md            # Nutzer, Quotas, Freigaben
    ├── nvme-ssd-guide.md              # M.2 NVMe SSD am Pi 5 (PCIe, Boot, Tuning)
    ├── performance-tuning.md          # SMB-Tuning, I/O-Scheduler, etc.
    └── backup-strategie.md            # Backup-Konzept
```

---

## Härtung (übernommen + erweitert vom LLM-Stack)

Jeder Container folgt dem gleichen Härtungsmuster:

| Maßnahme | Details |
|---|---|
| `cap_drop: [ALL]` | Alle Linux-Capabilities entfernt |
| `security_opt: [no-new-privileges:true]` | Privilege Escalation blockiert |
| `pids_limit` | Schutz gegen Fork-Bombs |
| `read_only: true` (wo möglich) | Immutables Container-Rootfs |
| `tmpfs` für `/tmp`, `/run` | Flüchtige Schreibbereiche |
| Loopback-Binding `127.0.0.1:` | Kein direkter LAN/WAN-Zugriff auf Web-UIs |
| Image-Pinning | Exakte Versionen, kein `:latest` |
| `.env` mit `chmod 600` | Secrets geschützt |
| Cloudflare Tunnel (kein Port-Forwarding) | Zero offene WAN-Ports am Router |

Samba (Host): nur SMB3, kein Gastzugang, `hosts allow` auf LAN + Tailscale, systemd-Sandbox.

### Cloudflare Tunnel — Ein Connector, viele Subdomains

Genau wie beim LLM-Stack: **ein** `cloudflared`-Container bedient **alle** Public Hostnames.
Kein Port-Forwarding am Router nötig. Routing liegt komplett im Cloudflare Zero Trust Dashboard.

```text
cloudflared (Container, nas-network)
    │
    ├── cloud.nas-clemens.de  → http://nextcloud-aio-apache:11000
    ├── vault.nas-clemens.de  → http://vaultwarden:80
    ├── media.nas-clemens.de  → http://jellyfin:8096
    ├── files.nas-clemens.de  → http://filebrowser:8080      (nur Admin, Cloudflare Access)
    ├── home.nas-clemens.de   → http://homepage:3000         (Cloudflare Access)
    └── status.nas-clemens.de → http://uptime-kuma:3001      (Cloudflare Access)
```

---

## Schnellstart

```bash
# 1. Ordner vom PC auf den Pi kopieren (nach DietPi-Setup + SSH)
scp -r ~/Projekte/NAS root@<pi-ip>:/root/nas
ssh root@<pi-ip>
cd /root/nas

# 2. System + Platte vorbereiten
bash setup/01-dietpi-initial-setup.sh
bash setup/02-mount-usb-drive.sh        # ext4 + Quota
bash setup/03-docker-data-root.sh

# 3. Konfiguration
cp .env.example .env && chmod 600 .env && nano .env

# 4. Container + Samba
bash setup/04-deploy-stack.sh
bash setup/06-samba-host.sh

# 5. Nextcloud-Ersteinrichtung (AIO-Oberfläche per SSH-Tunnel, vom PC aus):
#    ssh -L 8180:127.0.0.1:8180 root@<pi-ip>   →   https://localhost:8180
#    Domain: cloud.nas-clemens.de

# 6. Nutzer anlegen (nachdem Nextcloud läuft)
chmod +x scripts/nas-user.sh
./scripts/nas-user.sh add clemi --smb none --cloud none --admin

# 7. Cloudflare Subdomains → bash setup/05-cloudflare-subdomains.sh
```

---

## Performance-Optimierung für maximale SMB-Geschwindigkeit

Der Pi 4B ist durch den **Gigabit-Ethernet-Port** und **USB 3.0** begrenzt auf:
- **~115 MB/s** (Gigabit-Ethernet theoretisch, praktisch ~110 MB/s)
- **~350 MB/s** USB 3.0 SSD (wird vom Netzwerk begrenzt)

Optimierungen in `configs/samba/smb.conf` und `setup/01-dietpi-initial-setup.sh`:
- `aio read size = 1` / `aio write size = 1` (Async I/O)
- `use sendfile = yes` (Zero-Copy)
- SMB3-Verschlüsselung im LAN aus (Pi 4 hat keine AES-Hardware → sonst nur ~30–50 MB/s)
- `min receivefile size = 16384`
- I/O-Scheduler: `mq-deadline` (für SSD) oder `bfq` (für HDD)
- `vm.dirty_ratio = 40` / `vm.dirty_background_ratio = 10`

→ Details in [`docs/performance-tuning.md`](file:///home/clemi/Projekte/NAS/docs/performance-tuning.md)
