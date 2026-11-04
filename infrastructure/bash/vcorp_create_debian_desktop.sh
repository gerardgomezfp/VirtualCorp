
#!/usr/bin/env bash

# ============================================================
# VirtualCorp - Creacio del template Debian Desktop amb Preseed
# Entorn: Debian natiu + VirtualBox
#
# Crea un template Debian Desktop amb LXQt i Falkon.
# La ISO de Debian es descarrega automaticament d'Internet.
# Les ISO es guarden al directori isos/ del projecte.
# En cas d'exit, els fitxers temporals s'eliminen.
# En cas d'error, es conserven a /tmp per facilitar el diagnostic.
# La maquina virtual i el seu disc no s'eliminen automaticament.
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ============================================================
# CONFIGURACIO DE DEBIAN
# ============================================================

debian_version="${DEBIAN_VERSION:-13.7.0}"
debian_arch="${DEBIAN_ARCH:-amd64}"

debian_iso_filename="debian-${debian_version}-${debian_arch}-netinst.iso"

debian_iso_url="https://cdimage.debian.org/debian-cd/${debian_version}/${debian_arch}/iso-cd/${debian_iso_filename}"

PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
ISO_DIR="${PROJECT_ROOT}/isos"

debian_iso_path="${DEBIAN_ISO_PATH:-${ISO_DIR}/${debian_iso_filename}}"

# ============================================================
# CONFIGURACIO DE LES PLANTILLES
# ============================================================

desktop_template_vmname="${DEBIAN_DESKTOP_TEMPLATE:-debian_desktop_template}"
sysadmin_user="sysadmin"

debian_memory="${DEBIAN_MEMORY:-2048}"
debian_cpus="${DEBIAN_CPUS:-2}"
debian_disk_size="${DEBIAN_DISK_SIZE_MB:-20480}"
debian_vm_group="${DEBIAN_TEMPLATE_GROUP:-$VM_TEMPLATES_GROUP}"
debian_internal_net="${DEBIAN_INTERNAL_NET:-debian-template-unused}"

desktop_hostname="deb-desktop-template"
desktop_partition_scheme="home"
desktop_tasks="standard,ssh-server"
desktop_packages="sudo xserver-xorg lxqt-core lightdm falkon"

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
        else
            log_warn "La instal·lacio no ha acabat correctament. Es conserven els fitxers temporals per diagnosticar l'error:"
            printf '  %s\n' "$download_folder" >&2
            log_warn "No s'ha eliminat cap VM ni cap disc virtual."
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

# ============================================================
# COMPROVACIO DE DEPENDENCIES
# ============================================================

check_prerequisites() {
    local cmd
    local key_file

    local required_commands=(
        sha256sum xorriso ssh-keygen openssl awk sed grep tr date
        mktemp sleep cmp rm chmod mkdir cat cp printf wget
    )

    log_info "Comprovant dependencies..."

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_err "Falta la dependencia: ${cmd}"
            log_err "Instal·la-la manualment abans de continuar."
            return 1
        fi
    done

    if [[ -z "${VBOXMANAGE_BIN:-}" || ! -x "$VBOXMANAGE_BIN" ]]; then
        log_err "No es troba VBoxManage."
        return 1
    fi

    for key_file in "$sysadmin_pub_key" "$auditor_pub_key"; do
        if [[ ! -s "$key_file" ]]; then
            log_err "No existeix la clau publica: ${key_file}"
            return 1
        fi

        if ! ssh-keygen -lf "$key_file" >/dev/null 2>&1; then
            log_err "La clau publica no es valida: ${key_file}"
            return 1
        fi
    done

    if vm_exists "$desktop_template_vmname"; then
        log_err "La VM ${desktop_template_vmname} ja existeix. No s'eliminara ni se sobreescriura."
        return 1
    fi

    mkdir -p "$ISO_DIR"

    download_folder="$(mktemp -d "${TMPDIR:-/tmp}/vcorp-debian.XXXXXX")"
    chmod 700 "$download_folder"

    log_ok "Dependencies i claus verificades."
}

# ============================================================
# DESCARREGA I VALIDACIO DE LA ISO DEBIAN
# ============================================================

deb_prepare_iso() {

    mkdir -p "$ISO_DIR"

    if [[ -s "$debian_iso_path" ]]; then
        log_info "ISO Debian existent: ${debian_iso_path}"
        log_info "Es reutilitzara la ISO existent."
    else
        log_info "Descarregant Debian ${debian_version}..."
        log_info "URL: ${debian_iso_url}"

        if ! wget -c -O "${debian_iso_path}.part" "$debian_iso_url"; then
            rm -f -- "${debian_iso_path}.part"
            log_err "No s'ha pogut descarregar la ISO Debian."
            return 1
        fi

        if [[ ! -s "${debian_iso_path}.part" ]]; then
            rm -f -- "${debian_iso_path}.part"
            log_err "La ISO descarregada esta buida."
            return 1
        fi

        mv -- "${debian_iso_path}.part" "$debian_iso_path"

        log_ok "ISO Debian descarregada correctament."
    fi

    log_info "Verificant el format de la ISO..."

    if ! xorriso -indev "$debian_iso_path" -toc >/dev/null 2>&1; then
        log_err "La ISO Debian no sembla valida o esta incompleta."
        return 1
    fi

    log_ok "ISO Debian preparada: ${debian_iso_path}"
}

# ============================================================
# CREACIO DEL PRESEED
# ============================================================

create_preseed() {
    local preseed_dir="$1"
    local hostname="$2"
    local partition_scheme="$3"
    local tasksel_packages="$4"
    local extra_packages="$5"
    local preseed_file="${preseed_dir}/preseed.cfg"
    local password_hash

    # Contrasenya de la plantilla Desktop: Asdqwe!23
    password_hash='$6$VCorpDesk2026$nMUTFoQlXjpoQrP2btWU/.pRSZtHLWKQA/Y1WZNoSsFyKHAho2U/ndNxH6og2.gkzuIud0T4g1koCKC8XRVFf0'

    cat > "$preseed_file" <<EOF_PRESEED
#_preseed_V1

### Localitzacio
d-i debian-installer/locale string es_ES.UTF-8
d-i localechooser/supported-locales multiselect es_ES.UTF-8
d-i keyboard-configuration/xkb-keymap select es

### Xarxa
d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean false
d-i netcfg/get_hostname string ${hostname}
d-i netcfg/get_domain string lan
d-i netcfg/wireless_wep string

### Mirror Debian
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

### Comptes
d-i passwd/root-login boolean false
d-i passwd/user-fullname string System Administrator
d-i passwd/username string ${sysadmin_user}
d-i passwd/user-password-crypted password ${password_hash}

### Hora
d-i clock-setup/utc boolean true
d-i time/zone string Europe/Madrid
d-i clock-setup/ntp boolean true

### Particionament automatic
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select ${partition_scheme}
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/device_remove_lvm boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

### APT i paquets
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/use_mirror boolean true
tasksel tasksel/first multiselect ${tasksel_packages}
d-i pkgsel/include string ${extra_packages}
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false

### Configuracio final
d-i preseed/late_command string set -e; mkdir -p /target/var/log; : > /target/var/log/vcorp-late-command.log; mark() { printf '%s\\n' "\$1" >> /target/var/log/vcorp-late-command.log; }; mark 'INICIO: late_command'; mark 'EJECUTANDO: 01 - crear directorio SSH'; mkdir -p /target/home/${sysadmin_user}/.ssh; mark 'OK: 01 - crear directorio SSH'; mark 'EJECUTANDO: 02 - copiar clave autorizada'; cp /cdrom/authorized_keys /target/home/${sysadmin_user}/.ssh/authorized_keys; mark 'OK: 02 - copiar clave autorizada'; mark 'EJECUTANDO: 03 - propietario del directorio SSH'; in-target chown -R ${sysadmin_user}:${sysadmin_user} /home/${sysadmin_user}/.ssh; mark 'OK: 03 - propietario del directorio SSH'; mark 'EJECUTANDO: 04 - permisos del directorio SSH'; in-target chmod 700 /home/${sysadmin_user}/.ssh; mark 'OK: 04 - permisos del directorio SSH'; mark 'EJECUTANDO: 05 - permisos de authorized_keys'; in-target chmod 600 /home/${sysadmin_user}/.ssh/authorized_keys; mark 'OK: 05 - permisos de authorized_keys'; mark 'EJECUTANDO: 06 - crear regla sudoers'; printf '%s\\n' '${sysadmin_user} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${sysadmin_user}; mark 'OK: 06 - crear regla sudoers'; mark 'EJECUTANDO: 07 - permisos de sudoers'; chmod 440 /target/etc/sudoers.d/${sysadmin_user}; mark 'OK: 07 - permisos de sudoers'; mark 'EJECUTANDO: 08 - validar sudoers con visudo'; in-target visudo -cf /etc/sudoers.d/${sysadmin_user}; mark 'OK: 08 - validar sudoers con visudo'; mark 'EJECUTANDO: 09 - crear directorio sshd_config.d'; mkdir -p /target/etc/ssh/sshd_config.d; mark 'OK: 09 - crear directorio sshd_config.d'; mark 'EJECUTANDO: 10 - configurar autenticacion SSH'; printf '%s\\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PubkeyAuthentication yes' > /target/etc/ssh/sshd_config.d/99-vcorp-key-only.conf; mark 'OK: 10 - configurar autenticacion SSH'; mark 'EJECUTANDO: 11 - crear servicio de claves SSH'; printf '%s\\n' '[Unit]' 'Description=Generate SSH host keys on first boot' 'Before=ssh.service' 'ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key' '' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/ssh-keygen -A' 'RemainAfterExit=yes' '' '[Install]' 'WantedBy=multi-user.target' > /target/etc/systemd/system/vcorp-regenerate-ssh-hostkeys.service; mark 'OK: 11 - crear servicio de claves SSH'; mark 'EJECUTANDO: 12 - habilitar servicio SSH'; in-target systemctl enable ssh; mark 'OK: 12 - habilitar servicio SSH'; mark 'EJECUTANDO: 13 - habilitar servicio de regeneracion de claves'; in-target systemctl enable vcorp-regenerate-ssh-hostkeys.service; mark 'OK: 13 - habilitar servicio de regeneracion de claves'; mark 'EJECUTANDO: 14 - eliminar claves SSH de la plantilla'; rm -f /target/etc/ssh/ssh_host_*; mark 'OK: 14 - eliminar claves SSH de la plantilla'; mark 'EJECUTANDO: 15 - vaciar machine-id'; : > /target/etc/machine-id; mark 'OK: 15 - vaciar machine-id'; mark 'EJECUTANDO: 16 - eliminar machine-id de D-Bus'; rm -f /target/var/lib/dbus/machine-id; mark 'OK: 16 - eliminar machine-id de D-Bus'; mark 'EJECUTANDO: 17 - enlazar machine-id de D-Bus'; ln -s /etc/machine-id /target/var/lib/dbus/machine-id; mark 'OK: 17 - enlazar machine-id de D-Bus'; mark 'FINALIZADO: late_command'

### GRUB
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean false
d-i grub-installer/bootdev string /dev/sda

### Finalitzacio automatica
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/poweroff boolean true
EOF_PRESEED

    chmod 600 "$preseed_file"

    if ! grep -q '^d-i preseed/late_command string set -e;' "$preseed_file"; then
        log_err "El late_command no s'ha generat com una sola ordre."
        return 1
    fi

    if grep -q '\\\\$' "$preseed_file"; then
        log_err "S'han detectat continuacions de linia sospitoses al Preseed."
        return 1
    fi

    if ! grep -q "passwd/username string ${sysadmin_user}" "$preseed_file"; then
        log_err "No s'ha configurat l'usuari sysadmin al Preseed."
        return 1
    fi

    log_ok "Preseed creat i validat: ${preseed_file}"
}

# ============================================================
# CREACIO I VALIDACIO DE LA ISO PERSONALITZADA
# ============================================================

deb_create_preseeded_iso() {
    local work_dir="$1" hostname="$2" partition_scheme="$3"
    local tasksel_packages="$4" extra_packages="$5" output_iso="$6"
    local preseed_file="${work_dir}/preseed.cfg"
    local authorized_keys="${work_dir}/authorized_keys"
    local isolinux_txt="${work_dir}/txt.cfg"
    local isolinux_cfg="${work_dir}/isolinux.cfg"
    local grub_cfg="${work_dir}/grub.cfg"
    local verify_dir="${work_dir}/verify"
    local boot_report="${work_dir}/el-torito-report.txt"

    mkdir -p "$work_dir" "$verify_dir"

    {
        cat "$sysadmin_pub_key"
        printf '\n'
        cat "$auditor_pub_key"
        printf '\n'
    } > "$authorized_keys"

    chmod 600 "$authorized_keys"

    create_preseed "$work_dir" "$hostname" "$partition_scheme" "$tasksel_packages" "$extra_packages"

    log_info "Preparant configuracions d'arrencada per a ${hostname}..."

    xorriso -osirrox on -indev "$debian_iso_path" \
        -extract /isolinux/txt.cfg "$isolinux_txt" \
        -extract /isolinux/isolinux.cfg "$isolinux_cfg" \
        -extract /boot/grub/grub.cfg "$grub_cfg" >/dev/null
    # Donar permisos d'escriptura als fitxers extrets de la ISO.
    chmod u+rw "$isolinux_txt" "$isolinux_cfg" "$grub_cfg"
    # Afegir els parametres abans de ---.
    sed -i -E \
        's/[[:space:]]---/ auto=true priority=critical locale=es_ES.UTF-8 keyboard-configuration\/xkb-keymap=es preseed\/file=\/cdrom\/preseed.cfg ---/g' \
        "$isolinux_txt" "$grub_cfg"

    if ! grep -q 'preseed/file=/cdrom/preseed.cfg' "$isolinux_txt"; then
        log_err "No s'ha pogut afegir Preseed a la configuracio BIOS."
        return 1
    fi

    if ! grep -q 'preseed/file=/cdrom/preseed.cfg' "$grub_cfg"; then
        log_err "No s'ha pogut afegir Preseed a la configuracio UEFI."
        return 1
    fi

    if grep -qE '^[[:space:]]*default[[:space:]]' "$isolinux_cfg"; then
        sed -i -E 's/^[[:space:]]*default[[:space:]].*/default install/' "$isolinux_cfg"
    else
        printf '\ndefault install\n' >> "$isolinux_cfg"
    fi

    if grep -qE '^[[:space:]]*timeout[[:space:]]' "$isolinux_cfg"; then
        sed -i -E 's/^[[:space:]]*timeout[[:space:]].*/timeout 10/' "$isolinux_cfg"
    else
        printf 'timeout 10\n' >> "$isolinux_cfg"
    fi

    if grep -qE '^[[:space:]]*prompt[[:space:]]' "$isolinux_cfg"; then
        sed -i -E 's/^[[:space:]]*prompt[[:space:]].*/prompt 0/' "$isolinux_cfg"
    else
        printf 'prompt 0\n' >> "$isolinux_cfg"
    fi

    if grep -qE '^[[:space:]]*set timeout=' "$grub_cfg"; then
        sed -i -E 's/^[[:space:]]*set timeout=.*/set timeout=0/' "$grub_cfg"
    else
        printf '\nset timeout=0\n' >> "$grub_cfg"
    fi

    if grep -qE '^[[:space:]]*set timeout_style=' "$grub_cfg"; then
        sed -i -E 's/^[[:space:]]*set timeout_style=.*/set timeout_style=hidden/' "$grub_cfg"
    else
        printf 'set timeout_style=hidden\n' >> "$grub_cfg"
    fi

    log_info "Creant ISO personalitzada per a ${hostname}..."

    xorriso -indev "$debian_iso_path" -outdev "$output_iso" \
        -boot_image any replay \
        -map "$preseed_file" /preseed.cfg \
        -map "$authorized_keys" /authorized_keys \
        -map "$isolinux_txt" /isolinux/txt.cfg \
        -map "$isolinux_cfg" /isolinux/isolinux.cfg \
        -map "$grub_cfg" /boot/grub/grub.cfg \
        -commit -end >/dev/null

    if [[ ! -s "$output_iso" ]]; then
        log_err "No s'ha creat la ISO personalitzada."
        return 1
    fi

    # Verificar el Preseed, les claus SSH i l'arrencada BIOS/UEFI.
    xorriso -osirrox on -indev "$output_iso" \
        -extract /preseed.cfg "${verify_dir}/preseed.cfg" \
        -extract /authorized_keys "${verify_dir}/authorized_keys" \
        -extract /isolinux/txt.cfg "${verify_dir}/txt.cfg" \
        -extract /boot/grub/grub.cfg "${verify_dir}/grub.cfg" >/dev/null

    cmp -s "$preseed_file" "${verify_dir}/preseed.cfg" || {
        log_err "El Preseed dins la ISO no coincideix amb el fitxer generat."
        return 1
    }

    cmp -s "$authorized_keys" "${verify_dir}/authorized_keys" || {
        log_err "Les claus SSH dins la ISO no coincideixen amb les claus generades."
        return 1
    }

    grep -q 'preseed/file=/cdrom/preseed.cfg' "${verify_dir}/txt.cfg" || {
        log_err "La configuracio BIOS dins la ISO no conte el parametre Preseed."
        return 1
    }

    grep -q 'preseed/file=/cdrom/preseed.cfg' "${verify_dir}/grub.cfg" || {
        log_err "La configuracio UEFI dins la ISO no conte el parametre Preseed."
        return 1
    }

    xorriso -indev "$output_iso" -report_el_torito plain > "$boot_report" 2>&1

    if ! grep -qiE 'BIOS|legacy' "$boot_report" || ! grep -qi 'UEFI' "$boot_report"; then
        log_err "No s'han pogut verificar les entrades d'arrencada BIOS i UEFI de la ISO."
        log_err "Informe guardat a: ${boot_report}"
        return 1
    fi

    log_ok "ISO personalitzada creada i validada (Preseed, claus, BIOS i UEFI): ${output_iso}"
}

# ============================================================
# ESPERA DE FINALITZACIO DE LA INSTAL·LACIO
# ============================================================

wait_for_poweroff() {
    local vm_name="$1" max_wait="${2:-1800}"
    local start_time now state

    start_time="$(date +%s)"
    log_info "Esperant que ${vm_name} s'apagui automaticament (maxim ${max_wait}s)..."

    while true; do
        state="$("$VBOXMANAGE_BIN" showvminfo "$vm_name" --machinereadable \
            | sed -n 's/^VMState="\([^"]*\)".*/\1/p')"

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
            log_err "Temps d'espera esgotat per a ${vm_name}; la VM es conserva per investigar."
            return 1
        fi

        sleep 10
    done
}

# ============================================================
# CREACIO DE LA MAQUINA VIRTUAL
# ============================================================

deb_create_vm() {
    local vm_name="$1" custom_iso="$2" hostname="$3"
    local cfg_file vm_dir disk_path

    if vm_exists "$vm_name"; then
        log_err "La VM ${vm_name} ja existeix. No s'eliminara ni se sobreescriura."
        return 1
    fi

    log_info "Creant la VM ${vm_name}..."

    "$VBOXMANAGE_BIN" createvm --name "$vm_name" --ostype Debian_64 --register --groups "$debian_vm_group"

    "$VBOXMANAGE_BIN" modifyvm "$vm_name" \
        --memory "$debian_memory" --cpus "$debian_cpus" --ioapic on \
        --boot1 dvd --boot2 disk --boot3 none --boot4 none --nic1 nat

    cfg_file="$("$VBOXMANAGE_BIN" showvminfo "$vm_name" --machinereadable \
        | sed -n 's/^CfgFile="\(.*\)"/\1/p')"

    if [[ -z "$cfg_file" ]]; then
        log_err "No s'ha pogut trobar el directori de ${vm_name}."
        return 1
    fi

    vm_dir="$(dirname "$cfg_file")"
    disk_path="${vm_dir}/${vm_name}.vdi"

    "$VBOXMANAGE_BIN" createhd --filename "$disk_path" --size "$debian_disk_size" --format VDI

    "$VBOXMANAGE_BIN" storagectl "$vm_name" --name SATA --add sata --controller IntelAhci

    "$VBOXMANAGE_BIN" storageattach "$vm_name" \
        --storagectl SATA --port 0 --device 0 --type hdd --medium "$disk_path"

    "$VBOXMANAGE_BIN" storagectl "$vm_name" --name IDE --add ide

    "$VBOXMANAGE_BIN" storageattach "$vm_name" \
        --storagectl IDE --port 0 --device 0 --type dvddrive --medium "$custom_iso"

    log_info "Iniciant instal·lacio desatesa: ${hostname}..."

    "$VBOXMANAGE_BIN" startvm "$vm_name" --type headless
    wait_for_poweroff "$vm_name" 1800

    log_info "Desmuntant la ISO d'instal·lacio..."

    "$VBOXMANAGE_BIN" storageattach "$vm_name" \
        --storagectl IDE --port 0 --device 0 --medium none

    # No deixar NAT a la plantilla.
    "$VBOXMANAGE_BIN" modifyvm "$vm_name" \
        --nic1 intnet --intnet1 "$debian_internal_net" --cableconnected1 on \
        --boot1 disk --boot2 none --boot3 none --boot4 none

    log_info "Creant snapshot base..."

    "$VBOXMANAGE_BIN" snapshot "$vm_name" take base \
        --description "Debian ${debian_version} ${hostname} preparat per clonar"

    log_ok "Plantilla creada: ${vm_name}"
}

# ============================================================
# EXECUCIO PRINCIPAL
# ============================================================

main() {
    local desktop_work_dir desktop_iso

    check_prerequisites
    deb_prepare_iso

    desktop_work_dir="${download_folder}/desktop"
    desktop_iso="${download_folder}/debian-desktop-preseed.iso"

    mkdir -p "$desktop_work_dir"

    deb_create_preseeded_iso "$desktop_work_dir" "$desktop_hostname" \
        "$desktop_partition_scheme" "$desktop_tasks" "$desktop_packages" "$desktop_iso"

    deb_create_vm "$desktop_template_vmname" "$desktop_iso" "$desktop_hostname"

    deployment_success=true

    log_ok "La plantilla Debian Desktop s'ha creat correctament."
    log_info "Els fitxers temporals s'eliminaran; el disc i la maquina virtual es conservaran."
}

main "$@"
