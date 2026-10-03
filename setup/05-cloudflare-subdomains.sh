#!/bin/bash
# =============================================================================
#  05 — Cloudflare Tunnel Subdomains konfigurieren
#
#  ACHTUNG: Diese Datei ist eine ANLEITUNG, kein automatisches Skript.
#  Das Routing wird im Cloudflare Zero Trust Dashboard konfiguriert.
#
#  Voraussetzung: Tunnel existiert, Token steht in .env, der
#  cloudflared-Container läuft.
# =============================================================================

cat << 'ANLEITUNG'
===============================================================================
 Cloudflare Tunnel — Subdomains für NAS-Dienste
===============================================================================

Alle Schritte im Cloudflare Zero Trust Dashboard: https://one.dash.cloudflare.com/

1. EIGENEN Tunnel für das NAS erstellen (empfohlen)
───────────────────────────────────────────────────
  → Networks → Tunnels → Create a tunnel → Name: "nas-tunnel"
  → Token kopieren → in NAS/.env als TUNNEL_TOKEN= eintragen

  Der bestehende "openwebui-tunnel" auf dem PC bleibt unverändert.
  NICHT denselben Token wie auf dem PC verwenden: pro Token darf nur
  EIN Connector laufen (siehe LLM/ollama-zugriff, Kapitel 4).


2. Public Hostnames (Zero Trust → Networks → Tunnels → nas-tunnel)
──────────────────────────────────────────────────────────────────

  ┌─────────────────────────┬──────┬──────────────────────────────────────┐
  │ Subdomain               │ Type │ Service (Docker-Container-Name)      │
  ├─────────────────────────┼──────┼──────────────────────────────────────┤
  │ cloud.nas-clemens.de    │ HTTP │ http://nextcloud-aio-apache:11000    │
  │ vault.nas-clemens.de    │ HTTP │ http://vaultwarden:80                │
  │ media.nas-clemens.de    │ HTTP │ http://jellyfin:8096                 │
  │ files.nas-clemens.de    │ HTTP │ http://filebrowser:8080   (Admin!)   │
  │ home.nas-clemens.de     │ HTTP │ http://homepage:3000                 │
  │ status.nas-clemens.de   │ HTTP │ http://uptime-kuma:3001              │
  └─────────────────────────┴──────┴──────────────────────────────────────┘

  → Cloudflare legt die CNAME-Records (Proxied) automatisch an.
  → Nextcloud: der Apache-Container spricht intern HTTP; HTTPS macht Cloudflare.
  → Samba wird NICHT getunnelt (LAN bzw. Tailscale).


3. Cloudflare Access (Pflicht für Admin-Dienste)
────────────────────────────────────────────────
  Zero Trust → Access → Applications → Add → Self-hosted

  Mit Access-Policy (nur deine E-Mail, One-time PIN) absichern:
    - files.nas-clemens.de   (Filebrowser = voller Zugriff auf alle Shares)
    - home.nas-clemens.de    (Dashboard)
    - status.nas-clemens.de  (Monitoring)

  OHNE Access lassen (eigener Login + Apps/Sync-Clients brauchen direkten Zugang):
    - cloud.nas-clemens.de   (Nextcloud: Nutzer loggen sich dort ein, 2FA aktivieren)
    - vault.nas-clemens.de   (Bitwarden-Apps vertragen keine Access-Vorschaltseite)
    - media.nas-clemens.de   (Jellyfin-Apps, ebenso)


4. Hinweise
───────────
  - Cloudflare begrenzt Uploads auf 100 MB pro Request. Nextcloud-Clients
    laden in Stücken (Chunking) hoch, das passt. Nur sehr große Uploads
    über den Browser können scheitern.
  - Video-Streaming über Cloudflare ist laut deren Nutzungsbedingungen
    eine Grauzone. Für Jellyfin unterwegs ist Tailscale die sicherere Wahl.


5. Verifikation
───────────────
  docker logs --tail 20 cloudflared          # "Registered tunnel connection"
  dig +short cloud.nas-clemens.de            # → *.cfargotunnel.com
  curl -sI https://cloud.nas-clemens.de      # 200/302

===============================================================================
ANLEITUNG
