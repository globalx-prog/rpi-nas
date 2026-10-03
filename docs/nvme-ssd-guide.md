# NVMe SSD am Raspberry Pi 5 nutzen — Vollständige Anleitung

Der Raspberry Pi 5 verfügt über eine native **PCIe 2.0 / 3.0 x1 Schnittstelle** (FPC-Flachbandkabel-Anschluss).
Damit lassen sich M.2 NVMe SSDs direkt anschließen — entweder als ultraschneller Datenspeicher für das NAS oder sogar als primäres Boot-Laufwerk (ohne microSD-Karte).

---

## 1. Benötigte Hardware

1. **M.2 HAT+ Adapterboard** für den Raspberry Pi 5:
   * *Offiziell:* Raspberry Pi M.2 HAT+ (unterstützt M.2 2230 und 2242, ca. 12–14 €)
   * *Alternativen:* Geekworm X1001 / X1002, Waveshare PCIe to M.2, Pineberry Pi HatDrive (unterstützen oft auch lange 2280 NVMe SSDs)
2. **M.2 NVMe SSD:**
   * M.2 NVMe PCIe SSD (z. B. Kingston NV2, Crucial P3 / T500, Kioxia Exceria, WD Black / Blue)
   * Achte auf den Formfaktor (2230, 2242 oder 2280 je nach HAT-Board).

---

## 2. Hardware montieren & PCIe aktivieren

1. Pi 5 ausschalten und stromlos machen.
2. Das PCIe-Flachbandkabel vorsichtig am Pi 5 und am M.2 HAT befestigen.
3. NVMe SSD in den M.2-Slot einsetzen und verschrauben.
4. Pi 5 booten (zunächst von der microSD).

### PCIe in `/boot/firmware/config.txt` freischalten:

Öffne auf dem Pi die Boot-Konfiguration:
```bash
sudo nano /boot/firmware/config.txt
```
*(Bei älteren Versionen: `/boot/config.txt`)*

Füge ganz unten folgende Zeilen hinzu:

```ini
# PCIe-Port für M.2 NVMe SSD aktivieren
dtparam=pciex1

# Optional: PCIe Gen 3 Geschwindigkeit aktivieren (bis zu ~850 MB/s statt ~450 MB/s)
dtparam=pciex1_gen=3
```

Speichern (`Strg+O`, `Enter`, `Strg+X`) und Pi neu starten:
```bash
sudo reboot
```

---

## 3. SSD im System prüfen

Nach dem Reboot prüfen, ob die SSD erkannt wird:

```bash
# 1. PCIe-Gerät prüfen:
lspci
# Sollte z.B. "Non-Volatile memory controller" anzeigen

# 2. Block-Geräte anzeigen:
lsblk
```

Die NVMe SSD erscheint in Linux als **`/dev/nvme0n1`** (und nicht wie USB-Platten als `/dev/sda`).

---

## 4. Nutzungsszenarien

### Szenario A: NVMe SSD als NAS-Datenplatte nutzen (Boot von microSD)
Die microSD bleibt das Betriebssystem, die NVMe SSD speichert alle NAS-Daten, Docker-Volumes und Freigaben.

Führe einfach unser Setup-Skript aus:
```bash
cd /root/nas
sudo bash setup/02-mount-usb-drive.sh
```
* Wenn das Skript nach der Partition fragt, gibst du einfach die NVMe-Partition ein (z. B. `/dev/nvme0n1p1`).
* Das Skript formatiert sie als `ext4`, aktiviert Kernel-Quotas, trägt sie mit optimierten Mount-Optionen (`noatime,lazytime,commit=60`) in die `/etc/fstab` ein und setzt den schnellen `mq-deadline` I/O-Scheduler.

---

### Szenario B: Vollständig von NVMe SSD booten (Keine microSD mehr nötig!)

Der Raspberry Pi 5 kann direkt und rasend schnell von der NVMe SSD booten.

#### Schritt 1: Boot-Reihenfolge im EEPROM anpassen
```bash
sudo rpi-eeprom-config --edit
```
Ändere oder ergänze die Zeile `BOOT_ORDER`:
```ini
BOOT_ORDER=0xf416
```
*(Die Ziffer `6` steht für NVMe-Boot: Zuerst versucht der Pi von NVMe zu booten, danach von SD `1`, danach USB `4`)*.

Speichern und schließen.

#### Schritt 2: System von microSD auf NVMe klonen
In DietPi ist dafür ein komfortables Tool bereits eingebaut:
```bash
sudo dietpi-drive_manager
```
1. Wähle die NVMe SSD (`/dev/nvme0n1`).
2. Wähle **"Clone system to this drive"** (bzw. System spiegeln).
3. Sobald der Klonvorgang abgeschlossen ist: Pi herunterfahren (`sudo poweroff`), microSD-Karte entfernen und Pi 5 einschalten.
4. Der Pi 5 bootet nun in unter 8 Sekunden direkt von der M.2 SSD!

---

## 5. Geschwindigkeitsvergleich am Pi 5

| Medium | Lese-Rate | Schreib-Rate | Latenz / Random IOPS |
|---|---|---|---|
| microSD-Karte (UHS-I) | ~40–45 MB/s | ~20–30 MB/s | Sehr langsam |
| Externe USB 3.0 HDD | ~110–130 MB/s | ~100–120 MB/s | Langsam |
| Externe USB 3.0 SATA-SSD | ~350–380 MB/s | ~320–360 MB/s | Gut |
| **M.2 NVMe SSD (PCIe Gen 2)** | **~450 MB/s** | **~420 MB/s** | **Hervorragend** |
| **M.2 NVMe SSD (PCIe Gen 3)** | **~850–900 MB/s** | **~800 MB/s** | **Maximal** |
