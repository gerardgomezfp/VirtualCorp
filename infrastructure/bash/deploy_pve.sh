#!/usr/bin/env bash

# ============================================================
# VirtualCorp - Instal·lacio desatesa de Proxmox VE (pve01)
# Entorn: Debian natiu + VirtualBox (Sense requerir sudo)
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOCAL_BIN_DIR="${PROJECT_ROOT}/infrastructure/bin"
ASSISTANT_BIN="${LOCAL_BIN_DIR}/proxmox-auto-install-assistant"

# ============================================================
# CONFIGURACIO DE PROXMOX
# ============================================================

pve_version="${PVE_VERSION:-9.2-1}"
pve_iso_filename="proxmox-ve_${pve_version}.iso"
pve_iso_url="${PVE_ISO_URL:-https://download.proxmox.com/iso/${pve_iso_filename}}"

pve_iso_dir="${PVE_ISO_DIR:-${TMPDIR:-/tmp}/vcorp-isos}"
pve_iso_path="${PVE_ISO_PATH:-${pve_iso_dir}/${pve_iso_filename}}"
pve_iso_managed=true
[[ -n "${PVE_ISO_PATH:-}" ]] && pve_iso_managed=false
pve_keep_iso="${PVE_KEEP_ISO:-false}"

# ============================================================
# CONFIGURACIO DE LA MAQUINA
# ============================================================

pve_vmname="${PVE_VM_NAME:-pve01}"
pve_domain="${PVE_DOMAIN:-lan}"
pve_cidr="${PVE_CIDR:-10.8.0.133/26}"
pve_gateway="${PVE_GATEWAY:-10.8.0.129}"
pve_dns="${PVE_DNS:-${pve_gateway}}"
pve_internal_net="${PVE_INTERNAL_NET:-privada}"

pve_memory="${PVE_MEMORY:-8192}"
pve_cpus="${PVE_CPUS:-4}"
pve_disk_size="${PVE_DISK_SIZE_MB:-65536}"
pve_vm_group="${PVE_VM_GROUP:-${VM_EQUIPMENT_GROUP:-}}"
pve_basefolder="${VM_EQUIPMENT_BASEFOLDER:-}"

pve_root_password_hash="${PVE_ROOT_PASSWORD_HASH:-\$6\$VCorpDesk2026\$nMUTFoQlXjpoQrP2btWU/.pRSZtHLWKQA/Y1WZNoSsFyKHAho2U/ndNxH6og2.gkzuIud0T4g1koCKC8XRVFf0}"

sysadmin_pub_key="${SSH_PUBLIC_KEY_DIR}/vcorp_sysadmin.pub"
auditor_pub_key="${SSH_PUBLIC_KEY_DIR}/vcorp_auditor.pub"

download_folder=""
deployment_success=false

# ============================================================
# NETEJA I GESTIO D'ERRORS
# ============================================================

cleanup() {
    local result=$?
    trap - EXIT

    if [[ -n "${download_folder:-}" && -d "$download_folder" ]]; then
        if [[ "$deployment_success" == true && $result -eq 0 ]]; then
            log_info "Eliminant fitxers temporals..."
            rm -rf -- "$download_folder"

            if [[ "$pve_iso_managed" == true && "$pve_keep_iso" != true && -f "$pve_iso_path" ]]; then
                log_info "Eliminant la ISO original de Proxmox..."
                rm -f -- "$pve_iso_path"
                rmdir --ignore-fail-on-non-empty "$pve_iso_dir" 2>/dev/null || true
            fi
        else
            log_warn "La instal·lacio no ha acabat correctament. Es conserven els fitxers temporals."
        fi
    fi
}

on_error() {
    local rc=$?
    printf '\n[ERROR] Error a la linia %s (codi %s).\n' "${BASH_LINENO[0]:-?}" "$rc" >&2
    exit "$rc"
}

trap cleanup EXIT
trap on_error ERR

# ============================================================
# FUNCIONS AUXILIARS
# ============================================================

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" >/dev/null 2>&1
}

check_free_space() {
    local dir="$1" needed_mb="$2" free_mb
    mkdir -p "$dir"
    free_mb="$(df -Pm -- "$dir" | awk 'NR==2 {print $4}')"
    if [[ -z "$free_mb" ]] || (( free_mb < needed_mb )); then
        log_err "Espai insuficient a ${dir}: ${free_mb:-?} MB lliures, calen ${needed_mb} MB."
        return 1
    fi
}

# ============================================================
# GESTIO LOCAL DE DEPENDENCIES (SENSE SUDO)
# ============================================================

setup_local_assistant() {
    if [[ -x "$ASSISTANT_BIN" ]]; then
        return 0
    fi

    log_info "Configurant proxmox-auto-install-assistant en mode usuari (sense sudo)..."
    mkdir -p "$LOCAL_BIN_DIR"

    local temp_pkg_dir
    temp_pkg_dir="$(mktemp -d)"

    # Descarregar el fitxer Packages del repositori oficial de Proxmox per a trixie
    if ! wget -qO "${temp_pkg_dir}/Packages" "http://download.proxmox.com/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/Packages"; then
        log_err "No s'ha pogut connectar amb el repositori de Proxmox."
        rm -rf "$temp_pkg_dir"
        return 1
    fi

    local deb_rel_path
    deb_rel_path="$(awk '/^Package: proxmox-auto-install-assistant$/ {found=1} found && /^Filename: / {print $2; exit}' "${temp_pkg_dir}/Packages")"

    if [[ -z "$deb_rel_path" ]]; then
        log_err "No s'ha trobat el paquet proxmox-auto-install-assistant al repositori."
        rm -rf "$temp_pkg_dir"
        return 1
    fi

    local deb_url="http://download.proxmox.com/debian/pve/${deb_rel_path}"
    local deb_file="${temp_pkg_dir}/assistant.deb"

    log_info "Descarregant paquet .deb..."
    wget -qO "$deb_file" "$deb_url"

    log_info "Extreient binari en entorn local..."
    dpkg-deb -x "$deb_file" "${temp_pkg_dir}/extracted"

    if [[ -f "${temp_pkg_dir}/extracted/usr/bin/proxmox-auto-install-assistant" ]]; then
        cp "${temp_pkg_dir}/extracted/usr/bin/proxmox-auto-install-assistant" "$ASSISTANT_BIN"
        chmod +x "$ASSISTANT_BIN"
        log_ok "proxmox-auto-install-assistant preparat correctament a infrastructure/bin/"
    else
        log_err "No s'ha pogut extraure el binari correctament."
        rm -rf "$temp_pkg_dir"
        return 1
    fi

    rm -rf "$temp_pkg_dir"
}

check_prerequisites() {
    local cmd key_file
    local required_commands=(sha256sum xorriso ssh-keygen awk sed grep tr date mktemp sleep rm rmdir chmod mkdir cat cp printf wget head df dpkg-deb)

    log_info "Comprovant dependencies..."

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_err "Falta la dependencia del sistema: ${cmd}"
            return 1
        fi
    done

    setup_local_assistant

    if [[ -z "${VBOXMANAGE_BIN:-}" || ! -x "$VBOXMANAGE_BIN" ]]; then
        log_err "No es troba VBoxManage."
        return 1
    fi

    for key_file in "$sysadmin_pub_key" "$auditor_pub_key"; do
        if [[ ! -s "$key_file" ]]; then
            log_err "No existeix la clau publica: ${key_file}"
            return 1
        fi
    done

    if vm_exists "$pve_vmname"; then
        log_warn "La VM '${pve_vmname}' ja existeix. S'omet el desplegament."
        deployment_success=true
        exit 0
    fi

    check_free_space "$pve_iso_dir" 3000
    download_folder="$(mktemp -d "${TMPDIR:-/tmp}/vcorp-proxmox.XXXXXX")"
    chmod 700 "$download_folder"

    log_ok "Dependencies i entorn verificats."
}

# ============================================================
# DESCARREGA DE LA ISO PROXMOX
# ============================================================

pve_prepare_iso() {
    mkdir -p "$pve_iso_dir"

    if [[ -s "$pve_iso_path" ]]; then
        log_info "ISO Proxmox existent: ${pve_iso_path}"
    else
        log_info "Descarregant Proxmox VE ${pve_version}..."
        if ! wget -c --no-check-certificate -O "${pve_iso_path}.part" "$pve_iso_url"; then
            rm -f -- "${pve_iso_path}.part"
            log_err "No s'ha pogut descarregar la ISO Proxmox."
            return 1
        fi
        mv -- "${pve_iso_path}.part" "$pve_iso_path"
        log_ok "ISO Proxmox descarregada."
    fi
}

# ============================================================
# CREACIO DE L'ANSWER FILE
# ============================================================

pve_create_answer_file() {
    local answer_file="$1"
    local key_file key

    cat > "$answer_file" <<EOF
[global]
keyboard = "es"
country = "es"
fqdn = "${pve_vmname}.${pve_domain}"
mailto = "root@localhost"
timezone = "Europe/Madrid"
root-password-hashed = "${pve_root_password_hash}"
root-ssh-keys = [
EOF

    for key_file in "$sysadmin_pub_key" "$auditor_pub_key"; do
        key="$(head -n1 "$key_file" | tr -d '\r')"
        echo "  \"${key}\"," >> "$answer_file"
    done

    cat >> "$answer_file" <<EOF
]
reboot-mode = "power-off"
reboot-on-error = false

[network]
source = "from-answer"
cidr = "${pve_cidr}"
dns = "${pve_dns}"
gateway = "${pve_gateway}"

[network.filter]
ID_NET_NAME = "en*"

[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
lvm.swapsize = 2
EOF

    chmod 600 "$answer_file"

    log_info "Validant l'answer file..."
    "$ASSISTANT_BIN" validate-answer "$answer_file"
    log_ok "Answer file creat i validat: ${answer_file}"
}
# ============================================================
# CREACIO DE LA ISO PERSONALITZADA
# ============================================================

pve_create_auto_iso() {
    local answer_file="$1" output_iso="$2"

    log_info "Creant ISO d'instal·lacio desatesa amb proxmox-auto-install-assistant..."
    "$ASSISTANT_BIN" prepare-iso "$pve_iso_path" \
        --fetch-from iso \
        --answer-file "$answer_file" \
        --output "$output_iso"

    if [[ ! -s "$output_iso" ]]; then
        log_err "No s'ha creat la ISO personalitzada."
        return 1
    fi
    log_ok "ISO personalitzada creada: ${output_iso}"
}

# ============================================================
# ESPERA DE FINALITZACIO DE LA INSTAL·LACIO
# ============================================================

wait_for_poweroff() {
    local vm_name="$1" max_wait="${2:-2400}"
    local start_time now state

    start_time="$(date +%s)"
    log_info "Esperant que ${vm_name} s'apagui automaticament (maxim ${max_wait}s)..."

    while true; do
        state="$("$VBOXMANAGE_BIN" showvminfo "$vm_name" --machinereadable | sed -n 's/^VMState="\([^"]*\)".*/\1/p')"

        case "$state" in
            poweroff)
                log_ok "La VM ${vm_name} s'ha apagat."
                return 0
                ;;
            aborted|paused|saved)
                log_err "La VM ${vm_name} ha acabat en un estat inesperat: ${state}."
                return 1
                ;;
        esac

        now="$(date +%s)"
        if (( now - start_time >= max_wait )); then
            log_err "Temps d'espera esgotat per a ${vm_name}."
            return 1
        fi
        sleep 10
    done
}

# ============================================================
# CREACIO DE LA MAQUINA VIRTUAL
# ============================================================

pve_create_vm() {
    local vm_name="$1" custom_iso="$2"
    local cfg_file vm_dir disk_path

    log_info "Creant la VM ${vm_name}..."

    if [[ -n "${pve_vm_group}" && -n "${pve_basefolder}" ]]; then
        "$VBOXMANAGE_BIN" createvm --name "$vm_name" --ostype Debian_64 --register --groups "$pve_vm_group" --basefolder "$pve_basefolder"
    elif [[ -n "${pve_vm_group}" ]]; then
        "$VBOXMANAGE_BIN" createvm --name "$vm_name" --ostype Debian_64 --register --groups "$pve_vm_group"
    elif [[ -n "${pve_basefolder}" ]]; then
        "$VBOXMANAGE_BIN" createvm --name "$vm_name" --ostype Debian_64 --register --basefolder "$pve_basefolder"
    else
        "$VBOXMANAGE_BIN" createvm --name "$vm_name" --ostype Debian_64 --register
    fi

    "$VBOXMANAGE_BIN" modifyvm "$vm_name" \
        --memory "$pve_memory" --cpus "$pve_cpus" --ioapic on \
        --nested-hw-virt on \
        --boot1 dvd --boot2 disk --boot3 none --boot4 none \
        --nic1 intnet --intnet1 "$pve_internal_net" \
        --nicpromisc1 allow-all --cableconnected1 on

    cfg_file="$("$VBOXMANAGE_BIN" showvminfo "$vm_name" --machinereadable | sed -n 's/^CfgFile="\(.*\)"/\1/p')"
    vm_dir="$(dirname "$cfg_file")"
    disk_path="${vm_dir}/${vm_name}.vdi"

    "$VBOXMANAGE_BIN" createhd --filename "$disk_path" --size "$pve_disk_size" --format VDI
    "$VBOXMANAGE_BIN" storagectl "$vm_name" --name SATA --add sata --controller IntelAhci
    "$VBOXMANAGE_BIN" storageattach "$vm_name" --storagectl SATA --port 0 --device 0 --type hdd --medium "$disk_path"
    "$VBOXMANAGE_BIN" storagectl "$vm_name" --name IDE --add ide
    "$VBOXMANAGE_BIN" storageattach "$vm_name" --storagectl IDE --port 0 --device 0 --type dvddrive --medium "$custom_iso"

    log_info "Iniciant instal·lacio desatesa de Proxmox VE a ${vm_name}..."
    "$VBOXMANAGE_BIN" startvm "$vm_name" --type headless
    wait_for_poweroff "$vm_name" 2400

    log_info "Desmuntant la ISO d'instal·lacio..."
    "$VBOXMANAGE_BIN" storageattach "$vm_name" --storagectl IDE --port 0 --device 0 --medium none
    "$VBOXMANAGE_BIN" modifyvm "$vm_name" --boot1 disk --boot2 none --boot3 none --boot4 none

    log_info "Creant snapshot post-install..."
    "$VBOXMANAGE_BIN" snapshot "$vm_name" take post-install \
        --description "Proxmox VE ${pve_version} acabat d'instal·lar (${pve_cidr})"

    log_ok "VM creada: ${vm_name}"
}

# ============================================================
# EXECUCIO PRINCIPAL
# ============================================================

main() {
    local answer_file auto_iso

    check_prerequisites
    pve_prepare_iso

    answer_file="${download_folder}/answer.toml"
    auto_iso="${download_folder}/proxmox-auto-install.iso"

    pve_create_answer_file "$answer_file"
    pve_create_auto_iso "$answer_file" "$auto_iso"
    pve_create_vm "$pve_vmname" "$auto_iso"

    deployment_success=true

    log_ok "Proxmox VE s'ha instal·lat correctament a ${pve_vmname} (${pve_cidr})."
}

main "$@"