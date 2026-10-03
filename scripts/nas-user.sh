#!/bin/bash
# =============================================================================
#  nas-user.sh — Zentrale Nutzerverwaltung für das Pi-NAS
#
#  Ein Befehl legt den Nutzer in BEIDEN Systemen an (gleiches Passwort):
#    1. Samba (LAN, schnell):  Linux-User + privater Ordner + ext4-Quota
#    2. Nextcloud (Cloud):     Nextcloud-User + Nextcloud-Quota
#
#  Ausführen auf dem Pi als root, z.B.:
#    sudo ./nas-user.sh add anna --smb 100G --cloud 20G
#    sudo ./nas-user.sh quota anna --smb 200G
#    sudo ./nas-user.sh list
# =============================================================================
set -euo pipefail

DATA_ROOT="${DATA_ROOT:-/mnt/data}"
USERS_DIR="$DATA_ROOT/shares/users"
NC_CONTAINER="${NC_CONTAINER:-nextcloud-aio-nextcloud}"
GROUP_USERS="nas-users"
GROUP_ADMINS="nas-admins"

# ----------------------------------------------------------------------------
usage() {
    cat << EOF
Verwendung: sudo $(basename "$0") <befehl> <name> [optionen]

Befehle:
  add    <name> [--smb GRÖSSE] [--cloud GRÖSSE] [--admin] [--no-cloud] [--no-smb]
  quota  <name> [--smb GRÖSSE] [--cloud GRÖSSE]
  passwd <name>
  del    <name> [--purge]          (--purge löscht auch den privaten Ordner)
  list

GRÖSSE: z.B. 500M, 20G, 1T  oder  none (= unbegrenzt)

Beispiele:
  $(basename "$0") add clemi --smb none --cloud none --admin
  $(basename "$0") add anna  --smb 100G --cloud 20G
  $(basename "$0") quota anna --cloud 50G
EOF
    exit 1
}

die()  { echo "FEHLER: $*" >&2; exit 1; }
info() { echo "  → $*"; }
warn() { echo "  ! $*" >&2; }

[[ $EUID -eq 0 ]] || die "Bitte als root ausführen (sudo)."

# ----------------------------------------------------------------------------
#  Hilfsfunktionen
# ----------------------------------------------------------------------------
validate_name() {
    [[ "$1" =~ ^[a-z][a-z0-9_-]{1,31}$ ]] \
        || die "Ungültiger Name '$1' (nur a-z, 0-9, _ und -; beginnt mit Buchstabe)."
}

validate_size() {
    [[ "$1" == "none" || "$1" =~ ^[0-9]+[MGT]$ ]] \
        || die "Ungültige Größe '$1' (Beispiele: 500M, 20G, 1T, none)."
}

# "20G" → KiB für setquota (0 = unbegrenzt)
size_to_kib() {
    [[ "$1" == "none" ]] && { echo 0; return; }
    echo $(( $(numfmt --from=iec "$1") / 1024 ))
}

# "20G" → "20 GB" für Nextcloud
size_to_nc() {
    [[ "$1" == "none" ]] && { echo "none"; return; }
    echo "${1%[MGT]} ${1: -1}B"
}

nc_available() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$NC_CONTAINER"
}

occ() {
    docker exec --user www-data "$NC_CONTAINER" php occ "$@"
}

read_password() {
    local p1 p2
    read -rsp "  Passwort für $1: " p1; echo
    read -rsp "  Passwort wiederholen: " p2; echo
    [[ "$p1" == "$p2" ]] || die "Passwörter stimmen nicht überein."
    [[ ${#p1} -ge 10 ]]  || die "Passwort zu kurz (mindestens 10 Zeichen)."
    PASSWORD="$p1"
}

set_smb_quota() {
    local name="$1" size="$2" kib
    kib=$(size_to_kib "$size")
    # Soft-Limit = 95 % (Warnung), Hard-Limit = Grenze
    setquota -u "$name" $(( kib * 95 / 100 )) "$kib" 0 0 "$DATA_ROOT"
    info "Samba-Quota: $size"
}

set_nc_quota() {
    local name="$1" size="$2"
    occ user:setting "$name" files quota "$(size_to_nc "$size")" >/dev/null
    info "Nextcloud-Quota: $size"
}

ensure_groups() {
    getent group "$GROUP_USERS"  >/dev/null || groupadd "$GROUP_USERS"
    getent group "$GROUP_ADMINS" >/dev/null || groupadd "$GROUP_ADMINS"
}

# ----------------------------------------------------------------------------
#  Optionen parsen
# ----------------------------------------------------------------------------
CMD="${1:-}"; [[ -n "$CMD" ]] || usage; shift
if [[ "$CMD" != "list" ]]; then
    NAME="${1:-}"; [[ -n "$NAME" ]] || usage; shift
    validate_name "$NAME"
fi

SMB_SIZE=""; CLOUD_SIZE=""; ADMIN=0; PURGE=0; DO_SMB=1; DO_CLOUD=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --smb)      SMB_SIZE="${2:-}";   validate_size "$SMB_SIZE";   shift 2 ;;
        --cloud)    CLOUD_SIZE="${2:-}"; validate_size "$CLOUD_SIZE"; shift 2 ;;
        --admin)    ADMIN=1;    shift ;;
        --purge)    PURGE=1;    shift ;;
        --no-smb)   DO_SMB=0;   shift ;;
        --no-cloud) DO_CLOUD=0; shift ;;
        *) usage ;;
    esac
done

# ----------------------------------------------------------------------------
#  Befehle
# ----------------------------------------------------------------------------
case "$CMD" in

# ---------------------------------------------------------------- add
add)
    ensure_groups
    SMB_SIZE="${SMB_SIZE:-50G}"
    CLOUD_SIZE="${CLOUD_SIZE:-10G}"
    read_password "$NAME"
    echo "Lege Nutzer '$NAME' an ..."

    if [[ $DO_SMB -eq 1 ]]; then
        if id "$NAME" &>/dev/null; then
            warn "Linux-User existiert bereits, wird wiederverwendet."
        else
            useradd --no-create-home --home-dir "$USERS_DIR/$NAME" \
                    --shell /usr/sbin/nologin --groups "$GROUP_USERS" "$NAME"
        fi
        usermod -aG "$GROUP_USERS" "$NAME"
        [[ $ADMIN -eq 1 ]] && usermod -aG "$GROUP_ADMINS" "$NAME"

        install -d -m 0700 -o "$NAME" -g "$NAME" "$USERS_DIR/$NAME"
        info "Privater Ordner: $USERS_DIR/$NAME  →  \\\\<pi>\\$NAME"

        printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -a -s "$NAME" >/dev/null
        smbpasswd -e "$NAME" >/dev/null
        info "Samba-Konto aktiv"
        set_smb_quota "$NAME" "$SMB_SIZE"
    fi

    if [[ $DO_CLOUD -eq 1 ]]; then
        if nc_available; then
            docker exec -e OC_PASS="$PASSWORD" --user www-data "$NC_CONTAINER" \
                php occ user:add --password-from-env --group users "$NAME" >/dev/null
            [[ $ADMIN -eq 1 ]] && occ group:adduser admin "$NAME" >/dev/null
            info "Nextcloud-Konto aktiv"
            set_nc_quota "$NAME" "$CLOUD_SIZE"
        else
            warn "Nextcloud-Container '$NC_CONTAINER' läuft nicht – Cloud-Konto übersprungen."
            warn "Später nachholen: $(basename "$0") add $NAME --no-smb --cloud $CLOUD_SIZE"
        fi
    fi
    echo "Fertig."
    ;;

# ---------------------------------------------------------------- quota
quota)
    [[ -n "$SMB_SIZE$CLOUD_SIZE" ]] || die "Mindestens --smb oder --cloud angeben."
    echo "Ändere Quota für '$NAME' ..."
    if [[ -n "$SMB_SIZE" ]]; then
        id "$NAME" &>/dev/null || die "Samba-Nutzer '$NAME' existiert nicht."
        set_smb_quota "$NAME" "$SMB_SIZE"
    fi
    if [[ -n "$CLOUD_SIZE" ]]; then
        nc_available || die "Nextcloud-Container läuft nicht."
        set_nc_quota "$NAME" "$CLOUD_SIZE"
    fi
    ;;

# ---------------------------------------------------------------- passwd
passwd)
    read_password "$NAME"
    if id "$NAME" &>/dev/null; then
        printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -s "$NAME" >/dev/null
        info "Samba-Passwort geändert"
    fi
    if nc_available; then
        docker exec -e OC_PASS="$PASSWORD" --user www-data "$NC_CONTAINER" \
            php occ user:resetpassword --password-from-env "$NAME" >/dev/null \
            && info "Nextcloud-Passwort geändert" \
            || warn "Kein Nextcloud-Konto '$NAME'."
    fi
    ;;

# ---------------------------------------------------------------- del
del)
    read -rp "Nutzer '$NAME' wirklich löschen? (ja/nein): " ok
    [[ "$ok" == "ja" ]] || die "Abgebrochen."

    if id "$NAME" &>/dev/null; then
        smbpasswd -x "$NAME" >/dev/null 2>&1 || true
        setquota -u "$NAME" 0 0 0 0 "$DATA_ROOT" || true
        if [[ $PURGE -eq 1 ]]; then
            rm -rf --one-file-system "${USERS_DIR:?}/$NAME"
            info "Privater Ordner gelöscht"
        else
            ARCHIVE="$DATA_ROOT/shares/backups/geloeschte-nutzer/$NAME-$(date +%Y%m%d)"
            mkdir -p "$(dirname "$ARCHIVE")"
            mv "$USERS_DIR/$NAME" "$ARCHIVE" 2>/dev/null && info "Ordner archiviert: $ARCHIVE"
        fi
        userdel "$NAME"
        info "Samba-/Linux-Konto gelöscht"
    fi
    if nc_available; then
        occ user:delete "$NAME" >/dev/null 2>&1 \
            && info "Nextcloud-Konto gelöscht (inkl. Cloud-Dateien!)" \
            || warn "Kein Nextcloud-Konto '$NAME'."
    fi
    ;;

# ---------------------------------------------------------------- list
list)
    printf '%-16s %-7s %12s %12s   %s\n' "NUTZER" "ADMIN" "SMB BELEGT" "SMB LIMIT" "CLOUD LIMIT"
    printf '%.0s─' {1..70}; echo
    members=$(getent group "$GROUP_USERS" | cut -d: -f4 | tr ',' ' ')
    for u in $members; do
        used=""; hard=""; adm="-"; id -nG "$u" | grep -qw "$GROUP_ADMINS" && adm="ja"
        # quota -w: eine Zeile pro Dateisystem; Felder: fs used soft hard ...
        read -r used hard < <(quota -u -w -s "$u" 2>/dev/null \
            | awk -v fs="$DATA_ROOT" '$1 ~ /^\// {print $2, $4; exit}') || true
        [[ "${hard:-0}" == "0" || "${hard:-0}" == "0K" ]] && hard="unbegrenzt"
        cloud="-"
        nc_available && cloud=$(occ user:setting "$u" files quota 2>/dev/null || echo "-")
        printf '%-16s %-7s %12s %12s   %s\n' "$u" "$adm" "${used:-0}" "${hard:-?}" "${cloud:-default}"
    done
    echo
    df -h "$DATA_ROOT" | awk 'NR==2 {print "Festplatte gesamt: " $2 ", belegt: " $3 ", frei: " $4}'
    ;;

*) usage ;;
esac
