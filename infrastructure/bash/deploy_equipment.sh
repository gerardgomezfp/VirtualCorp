#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Plantilles originals, que ja funcionen.
SERVER_TEMPLATE="${DEBIAN_SERVER_TEMPLATE:-debian_server_template}"
DESKTOP_TEMPLATE="${DEBIAN_DESKTOP_TEMPLATE:-debian_desktop_template}"

VM_MEMORY="${EQUIPMENT_MEMORY:-2048}"
VM_CPUS="${EQUIPMENT_CPUS:-2}"

# Inventari: nom | tipus | xarxa interna
EQUIPMENT=$(cat <<'INVENTORY'
dbsrv|server|privada
infosrv|server|privada
intrasrv|server|privada
websrv|server|dmz
coresrv|server|dmz
streamingsrv|server|dmz
printer0|server|pl0
printer1|server|pl1
printer2|server|pl2
printer3|server|pl3
web-p1|server|pl1
data-p1|server|pl1
web-p2|server|pl1
data-p2|server|pl1
web-p3|server|pl2
data-p3|server|pl2
expo1|desktop|pl0
expo2|desktop|pl0
expo3|desktop|pl0
expo4|desktop|pl0
conserge1|desktop|pl0
conserge2|desktop|pl0
dev1|desktop|pl1
dev2|desktop|pl2
Laptop2|desktop|pl3
Laptop3|desktop|pl3
directiu1|desktop|pl3_direccio
directiu2|desktop|pl3_direccio
directiu3|desktop|pl3_direccio
INVENTORY
)

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" >/dev/null 2>&1
}

check_template() {
    local template="$1"

    if ! vm_exists "$template"; then
        log_err "No existeix la plantilla: $template"
        return 1
    fi

    if ! "$VBOXMANAGE_BIN" snapshot "$template" list --details |
        grep -Fq 'Name: base'; then
        log_err "La plantilla $template no té el snapshot base."
        return 1
    fi

    log_ok "Plantilla disponible: $template"
}

check_internal_networks() {
    local required_networks=(
        privada dmz pl0 pl1 pl2 pl3 pl3_direccio
    )
    local available_networks network

    mapfile -t available_networks < <(
        "$VBOXMANAGE_BIN" list intnets |
            awk '$1 == "Name:" { print $2 }'
    )

    for network in "${required_networks[@]}"; do
        if ! printf '%s\n' "${available_networks[@]}" |
            grep -Fxq "$network"; then
            log_err "No existeix la xarxa interna: $network"
            return 1
        fi
    done

    log_ok "Tots els segments de xarxa existeixen."
}

clone_equipment() {
    local name="$1"
    local template="$2"
    local network="$3"

    if vm_exists "$name"; then
        log_warn "$name ja existeix; es conserva sense modificar."
        return 0
    fi

    log_info "Creant clon enllaçat: $name ($network)"

    "$VBOXMANAGE_BIN" clonevm "$template" \
        --snapshot=base \
        --mode=machine \
        --options=Link \
        --name="$name" \
        --groups="$VM_EQUIPMENT_GROUP" \
        --basefolder="$VM_EQUIPMENT_BASEFOLDER" \
        --register

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --memory "$VM_MEMORY" \
        --cpus "$VM_CPUS" \
        --nic1 intnet \
        --intnet1 "$network" \
        --cableconnected1 on \
        --nic2 none \
        --nic3 none \
        --nic4 none \
        --nic5 none \
        --nic6 none \
        --nic7 none \
        --nic8 none \
        --boot1 disk \
        --boot2 none \
        --boot3 none \
        --boot4 none

    log_ok "$name creada i connectada a $network."
}

main() {
    log_info "Comprovant requisits del desplegament..."

    if [[ ! -d "$VM_EQUIPMENT_BASEFOLDER" ]]; then
        log_err "No existeix la carpeta: $VM_EQUIPMENT_BASEFOLDER"
        return 1
    fi

    if [[ ! "$VM_MEMORY" =~ ^[0-9]+$ ]] ||
       [[ ! "$VM_CPUS" =~ ^[0-9]+$ ]] ||
       (( VM_MEMORY < 1 || VM_CPUS < 1 )); then
        log_err "La configuració de RAM o CPU no és vàlida."
        return 1
    fi

    check_template "$SERVER_TEMPLATE"
    check_template "$DESKTOP_TEMPLATE"
    check_internal_networks

    local created=0
    local skipped=0
    local name type network template

    while IFS='|' read -r name type network; do
        [[ -z "$name" ]] && continue

        case "$type" in
            server)  template="$SERVER_TEMPLATE" ;;
            desktop) template="$DESKTOP_TEMPLATE" ;;
            *)
                log_err "Tipus d'equip desconegut: $type"
                return 1
                ;;
        esac

        if vm_exists "$name"; then
            log_warn "$name ja existeix; no es modifica."
            ((skipped += 1))
            continue
        fi

        clone_equipment "$name" "$template" "$network"
        ((created += 1))
    done <<< "$EQUIPMENT"

    log_ok "Desplegament Debian finalitzat."
    log_info "Màquines noves: $created"
    log_info "Màquines conservades: $skipped"
}

main "$@"