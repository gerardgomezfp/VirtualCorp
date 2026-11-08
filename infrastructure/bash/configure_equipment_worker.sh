#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SSH_KEY="$SYSADMIN_PRIVATE_KEY_FILE"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-sysadmin}"
SSH_TARGET="127.0.0.1"
SSH_RULE="vcorp-config"
SSH_TIMEOUT=120

# name | internal network | IP | prefix | gateway
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
            echo "Ús: $0 --only nom_vm"
            exit 1
        }
        ONLY="$2"
        ;;
    *)
        echo "Ús: $0 [--all | --only nom_vm]"
        exit 1
        ;;
esac

for cmd in "$VBOXMANAGE_BIN" ssh timeout; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: no trobo l'ordre: $cmd"
        exit 1
    }
done

[[ -f "$SSH_KEY" ]] || {
    echo "ERROR: no existeix la clau privada: $SSH_KEY"
    exit 1
}

if ss -ltn 2>/dev/null | grep -qE "127\\.0\\.0\\.1:${SSH_PORT}[[:space:]]"; then
    echo "ERROR: el port local ${SSH_PORT} ja està ocupat."
    exit 1
fi

SSH_OPTS=(
    -p "$SSH_PORT"
    -i "$SSH_KEY"
    -o BatchMode=yes
    -o ConnectTimeout=3
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)

is_running() {
    "$VBOXMANAGE_BIN" showvminfo "$1" --machinereadable |
        grep -q '^VMState="running"$'
}

restore_vm() {
    local vm="$1"
    local network="$2"

    if is_running "$vm"; then
        "$VBOXMANAGE_BIN" controlvm "$vm" acpipowerbutton >/dev/null 2>&1 || true
        for _ in {1..30}; do
            is_running "$vm" || break
            sleep 2
        done
        if is_running "$vm"; then
            "$VBOXMANAGE_BIN" controlvm "$vm" poweroff >/dev/null 2>&1 || true
        fi
    fi

    "$VBOXMANAGE_BIN" modifyvm "$vm" --natpf1 delete "$SSH_RULE" \
        >/dev/null 2>&1 || true

    "$VBOXMANAGE_BIN" modifyvm "$vm" \
        --nic1 intnet \
        --intnet1 "$network" \
        --cableconnected1 on
}

configure_guest() {
    local name="$1"
    local ip="$2"
    local prefix="$3"
    local gateway="$4"

    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_TARGET}" \
        "sudo bash -s -- '$name' '$ip' '$prefix' '$gateway'" <<'REMOTE_EOF'
set -Eeuo pipefail

hostname="$1"
address="$2"
prefix="$3"
gateway="$4"

device="$(ip -o route show default |
    awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"

if [[ -z "$device" ]]; then
    echo "ERROR: no s'ha detectat la interfície de xarxa."
    exit 1
fi

hostnamectl set-hostname "$hostname"

if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    sed -i "s/^127\\.0\\.1\\.1.*/127.0.1.1\\t${hostname}/" /etc/hosts
else
    printf '127.0.1.1\t%s\n' "$hostname" >> /etc/hosts
fi

if command -v nmcli >/dev/null 2>&1 &&
   systemctl is-active --quiet NetworkManager; then

    connection="$(nmcli -g GENERAL.CONNECTION device show "$device")"

    if [[ -z "$connection" || "$connection" == "--" ]]; then
        echo "ERROR: NetworkManager no té connexió activa per a $device."
        exit 1
    fi

    nmcli connection modify "$connection" \
        ipv4.method manual \
        ipv4.addresses "$address/$prefix" \
        ipv4.gateway "$gateway" \
        ipv4.dns "" \
        ipv4.ignore-auto-dns yes \
        ipv6.method disabled

elif systemctl is-active --quiet systemd-networkd; then

    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/10-vcorp-static.network <<NETWORK_EOF
[Match]
Name=$device

[Network]
Address=$address/$prefix
Gateway=$gateway
NETWORK_EOF

    systemctl enable systemd-networkd

elif [[ -f /etc/network/interfaces ]]; then

    cp -a /etc/network/interfaces \
        /etc/network/interfaces.vcorp-backup

    cat > /etc/network/interfaces <<INTERFACES_EOF
source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

allow-hotplug $device
iface $device inet static
    address $address
    netmask $(python3 -c 'import ipaddress,sys; print(ipaddress.IPv4Network("0.0.0.0/"+sys.argv[1]).netmask)' "$prefix")
    gateway $gateway
INTERFACES_EOF

else
    echo "ERROR: no es reconegut el gestor de xarxa de Debian."
    exit 1
fi

echo "Configuració preparada:"
echo "Hostname: $hostname"
echo "Interfície: $device"
echo "IP: $address/$prefix"
echo "Gateway: $gateway"
REMOTE_EOF
}

configure_one() {
    local name="$1"
    local network="$2"
    local ip="$3"
    local prefix="$4"
    local gateway="$5"

    echo
    echo "========================================"
    echo "Configurant: $name"
    echo "Xarxa: $network | IP: $ip/$prefix"
    echo "========================================"

    if ! "$VBOXMANAGE_BIN" showvminfo "$name" >/dev/null 2>&1; then
        echo "ERROR: la VM $name no existeix."
        return 1
    fi

    if is_running "$name"; then
        echo "ERROR: $name ja està encesa. No es modificarà."
        return 1
    fi

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --nic1 nat \
        --cableconnected1 on

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --natpf1 "$SSH_RULE,tcp,127.0.0.1,$SSH_PORT,,22"

    "$VBOXMANAGE_BIN" startvm "$name" --type headless

    echo "Esperant SSH (màxim ${SSH_TIMEOUT}s)..."
    local connected=0

    for ((i=0; i<SSH_TIMEOUT; i++)); do
        if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_TARGET}" true \
            >/dev/null 2>&1; then
            connected=1
            break
        fi
        sleep 1
    done

    if [[ "$connected" -ne 1 ]]; then
        echo "ERROR: no s'ha pogut connectar per SSH a $name."
        restore_vm "$name" "$network"
        return 1
    fi

    if ! configure_guest "$name" "$ip" "$prefix" "$gateway"; then
        echo "ERROR: ha fallat la configuració interna de $name."
        restore_vm "$name" "$network"
        return 1
    fi

    restore_vm "$name" "$network"
    echo "OK: $name configurada. Xarxa interna restaurada."
}

success=0
failed=0
found=0

while IFS='|' read -r name network ip prefix gateway; do
    [[ -n "$name" ]] || continue

    if [[ -n "$ONLY" && "$name" != "$ONLY" ]]; then
        continue
    fi

    found=1
    if configure_one "$name" "$network" "$ip" "$prefix" "$gateway"; then
        ((success+=1))
    else
        ((failed+=1))
        if [[ -n "$ONLY" ]]; then
            break
        fi
    fi
done <<< "$INVENTORY"

if [[ "$found" -eq 0 ]]; then
    echo "ERROR: equip no trobat a l'inventari: $ONLY"
    exit 1
fi

echo
echo "========================================"
echo "Resultat: $success correctes, $failed fallides."
echo "========================================"

[[ "$failed" -eq 0 ]]