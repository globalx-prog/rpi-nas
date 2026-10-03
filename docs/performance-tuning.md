# Performance-Tuning für Raspberry Pi 4B NAS

## Hardware-Limits

| Schnittstelle | Theoretisch | Praktisch |
|---|---|---|
| Gigabit-Ethernet | 125 MB/s | ~110 MB/s |
| USB 3.0 (SSD) | 625 MB/s | ~350 MB/s |
| USB 3.0 (HDD) | 625 MB/s | ~120 MB/s |
| microSD (UHS-I) | 104 MB/s | ~40 MB/s |

> **Bottleneck:** Das Gigabit-Ethernet begrenzt die maximale SMB-Übertragungsrate
> auf ~110 MB/s — egal ob SSD oder HDD. Die SSD bringt aber Vorteile bei
> Random I/O (viele kleine Dateien, Docker-Container-Starts).

## SMB-Performance-Tuning

### Kernel-Parameter (`/etc/sysctl.d/99-nas-performance.conf`)

```conf
# TCP-Buffer — Standard ist viel zu klein für Gigabit-NAS
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Disk-I/O — Schreib-Cache vergrößern
vm.dirty_ratio = 40              # 40% RAM als Schreib-Cache
vm.dirty_background_ratio = 10   # Ab 10% beginnt Hintergrund-Flush
vm.dirty_expire_centisecs = 3000 # 30s bevor Dirty Pages verfallen

# Swap fast deaktivieren
vm.swappiness = 10

# Verzeichnis-Cache behalten
vm.vfs_cache_pressure = 50
```

### SMB-Optionen (in `smb.conf` / Docker ENV)

| Option | Wirkung |
|---|---|
| `aio read size = 1` | Async I/O ab 1 Byte (statt synchron) |
| `aio write size = 1` | Async I/O für Schreibvorgänge |
| `use sendfile = yes` | Zero-Copy: Kernel sendet Datei direkt an Socket |
| `min receivefile size = 16384` | Empfangene Daten direkt auf Platte schreiben |
| `socket options = TCP_NODELAY IPTOS_LOWDELAY` | Kein Nagle-Delay, Low-Latency-Routing |
| `strict locking = no` | Weniger Lock-Overhead |
| `read raw = yes` / `write raw = yes` | Bulk-Transfers aktivieren |
| `max xmit = 65535` | Maximale SMB-Paketgröße |
| `getwd cache = yes` | Verzeichnis-Pfad-Cache |
| `oplocks = yes` | Client-Caching (Opportunistic Locking) |

### I/O-Scheduler

| Laufwerkstyp | Scheduler | Warum |
|---|---|---|
| SSD | `mq-deadline` | Minimale Latenz, kein unnötiges Reordering |
| HDD | `bfq` | Budget Fair Queuing, gut für gemischte Workloads |

```bash
# Prüfen:
cat /sys/block/sda/queue/scheduler

# Setzen (temporär):
echo mq-deadline > /sys/block/sda/queue/scheduler

# Persistent via udev (siehe setup/02-mount-usb-drive.sh)
```

### Dateisystem-Optionen (ext4)

```
noatime     — Keine Zugriffszeitstempel (spart ~30% I/O)
lazytime    — Verzögerte Zeitstempel-Updates
commit=60   — Journal-Commits alle 60s statt 5s
```

## Benchmarking

### SMB-Geschwindigkeit testen (von einem anderen PC)

```bash
# Schreiben (1 GB Testdatei):
dd if=/dev/zero bs=1M count=1024 | \
  smbclient //PI-IP/documents -U clemi -c "put - testfile.bin"

# Oder mit mount:
sudo mount -t cifs //PI-IP/documents /mnt/nas -o username=clemi
dd if=/dev/zero of=/mnt/nas/testfile.bin bs=1M count=1024
dd if=/mnt/nas/testfile.bin of=/dev/null bs=1M

# Aufräumen:
rm /mnt/nas/testfile.bin
```

### Erwartete Werte (Pi 4B, Gigabit, ext4)

| Szenario | HDD | SSD |
|---|---|---|
| Sequentielles Lesen (große Dateien) | ~100–110 MB/s | ~110 MB/s (Ethernet-Limit) |
| Sequentielles Schreiben | ~90–100 MB/s | ~110 MB/s |
| Random Read (viele kleine Dateien) | ~1–5 MB/s | ~30–50 MB/s |
| Random Write | ~1–3 MB/s | ~20–40 MB/s |

## Docker-Performance auf dem Pi

### RAM-Budget (Pi 4B, 4 GB)

| Service | RAM (idle) | RAM (aktiv) |
|---|---|---|
| DietPi OS | ~50 MB | ~100 MB |
| Docker Engine | ~80 MB | ~150 MB |
| Samba | ~20 MB | ~50 MB |
| Filebrowser | ~15 MB | ~30 MB |
| cloudflared | ~15 MB | ~25 MB |
| Vaultwarden | ~15 MB | ~30 MB |
| Jellyfin | ~100 MB | ~500 MB (Transcoding!) |
| Homepage | ~30 MB | ~50 MB |
| Uptime Kuma | ~50 MB | ~80 MB |
| Watchtower | ~10 MB | ~30 MB |
| **Gesamt** | **~385 MB** | **~1.045 MB** |

> ~3 GB frei für Dateisystem-Cache — das ist der wichtigste
> Performance-Faktor für SMB-Transfers!

> [!WARNING]
> **Jellyfin-Transcoding** ist der größte RAM- und CPU-Fresser.
> Auf dem Pi 4B nur Direct Play/Direct Stream nutzen (Client muss
> das Format unterstützen). Hardware-Transcoding über V4L2 ist
> möglich, aber auf 1080p bei niedrigen Bitraten begrenzt.
