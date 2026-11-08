#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/common.sh"

WORKER="$SCRIPT_DIR/configure_equipment_worker.sh"
STATE_DIR="$PROJECT_DIR/configs/state"
STATE_FILE="$STATE_DIR/configured_equipment.tsv"

INVENTORY=$(cat <<'INVENTORY_EOF'
dbsrv|privada|10.8.0.134|26|10.8.0.129
infosrv|privada|10.8.0.135|26|10.8.0.129
intrasrv|privada|10.8.0.136|26|10.8.0.129
websrv|dmz|10.8.0.197|27|10.8.0.193
coresrv|dmz|10.8.0.198|27|10.8.0.193
streamingsrv|dmz|10.8.0.199|27|10.8.0.193
printer0|pl0|10.8.0.65|25|10.8.0.1
printer1|pl1|10.8.1.65|24|10.8.1.1
printer2|pl2|10.8.2.65|24|10.8.2.1
printer3|pl3|10.8.3.65|25|10.8.3.1
web-p1|pl1|10.8.1.10|24|10.8.1.1
data-p1|pl1|10.8.1.11|24|10.8.1.1
web-p2|pl1|10.8.1.12|24|10.8.1.1
data-p2|pl1|10.8.1.13|24|10.8.1.1
web-p3|pl2|10.8.2.10|24|10.8.2.1
data-p3|pl2|10.8.2.11|24|10.8.2.1
expo1|pl0|10.8.0.33|25|10.8.0.1
expo2|pl0|10.8.0.34|25|10.8.0.1
expo3|pl0|10.8.0.35|25|10.8.0.1
expo4|pl0|10.8.0.36|25|10.8.0.1
conserge1|pl0|10.8.0.37|25|10.8.0.1
conserge2|pl0|10.8.0.38|25|10.8.0.1
dev1|pl1|10.8.1.30|24|10.8.1.1
dev2|pl2|10.8.2.30|24|10.8.2.1
Laptop2|pl3|10.8.3.10|25|10.8.3.1
Laptop3|pl3|10.8.3.11|25|10.8.3.1
directiu1|pl3_direccio|10.8.3.130|25|10.8.3.129
directiu2|pl3_direccio|10.8.3.131|25|10.8.3.129
directiu3|pl3_direccio|10.8.3.132|25|10.8.3.129
INVENTORY_EOF
)

ONLY=""
case "${1:---all}" in
    --all) ;;
    --only)
        [[ $# -eq 2 ]] || {
            echo "Ús: $0 [--all | --only nom_vm]"
            exit 1
        }
        ONLY="$2"
        ;;
    *)
        echo "Ús: $0 [--all | --only nom_vm]"
        exit 1
        ;;
esac

[[ -x "$WORKER" ]] || {
    echo "ERROR: no existeix el script treballador: $WORKER"
    exit 1
}

mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

# dbsrv ja va completar correctament la primera configuració.
DBSRV_STATE="dbsrv|privada|10.8.0.134|26|10.8.0.129"
if ! grep -Fxq "$DBSRV_STATE" "$STATE_FILE"; then
    printf '%s\n' "$DBSRV_STATE" >> "$STATE_FILE"
fi

active_name=""
active_network=""

restore_active() {
    [[ -n "$active_name" ]] || return 0

    echo
    echo "Recuperant xarxa de $active_name..."

    if "$VBOXMANAGE_BIN" showvminfo "$active_name" >/dev/null 2>&1; then
        if "$VBOXMANAGE_BIN" showvminfo "$active_name" --machinereadable |
            grep -q '^VMState="running"$'; then
            "$VBOXMANAGE_BIN" controlvm "$active_name" poweroff \
                >/dev/null 2>&1 || true
        fi

        "$VBOXMANAGE_BIN" modifyvm "$active_name" \
            --natpf1 delete vcorp-config >/dev/null 2>&1 || true

        "$VBOXMANAGE_BIN" modifyvm "$active_name" \
            --nic1 intnet \
            --intnet1 "$active_network" \
            --cableconnected1 on
    fi

    active_name=""
    active_network=""
}

on_exit() {
    restore_active || true
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Recuperar dbsrv per si la interrupció anterior va deixar NAT actiu.
active_name="dbsrv"
active_network="privada"
restore_active

success=0
skipped=0
failed=0
found=0

while IFS='|' read -r name network ip prefix gateway; do
    [[ -n "$name" ]] || continue

    if [[ -n "$ONLY" && "$name" != "$ONLY" ]]; then
        continue
    fi

    found=1
    entry="$name|$network|$ip|$prefix|$gateway"

    if grep -Fxq "$entry" "$STATE_FILE"; then
        echo "SKIP: $name ja figura com a configurada ($ip/$prefix)."
        ((skipped+=1))
        continue
    fi

    # No continuar automàticament si existeix un registre antic
    # per a aquest equip amb una configuració diferent.
    if grep -q "^${name}|" "$STATE_FILE"; then
        echo "ERROR: el registre de $name no coincideix amb l'inventari."
        ((failed+=1))
        continue
    fi

    echo
    echo "----------------------------------------"
    echo "Processant $name"
    echo "----------------------------------------"

    active_name="$name"
    active_network="$network"

    if "$WORKER" --only "$name"; then
        # El treballador ja ha apagat la VM i restaurat la seva xarxa.
        active_name=""
        active_network=""

        printf '%s\n' "$entry" >> "$STATE_FILE"
        ((success+=1))
        echo "REGISTRADA: $name"
    else
        echo "ERROR: ha fallat $name."
        restore_active || true
        ((failed+=1))
    fi

done <<< "$INVENTORY"

if [[ "$found" -eq 0 ]]; then
    echo "ERROR: equip no trobat: $ONLY"
    exit 1
fi

echo
echo "========================================"
echo "RESUM DE CONFIGURACIÓ"
echo "Configurades ara:   $success"
echo "Ja configurades:    $skipped"
echo "Fallides:           $failed"
echo "========================================"

[[ "$failed" -eq 0 ]]