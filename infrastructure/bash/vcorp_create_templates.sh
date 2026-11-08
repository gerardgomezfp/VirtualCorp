
#!/usr/bin/env bash

# ============================================================
# VirtualCorp - Desplegament de plantilles Debian
#
# Crea les plantilles Server i Desktop si no existeixen.
# Les plantilles existents es conserven sense modificacions.
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/common.sh"

# ============================================================
# CONFIGURACIO
# ============================================================

server_template="${DEBIAN_SERVER_TEMPLATE:-debian_server_template}"
desktop_template="${DEBIAN_DESKTOP_TEMPLATE:-debian_desktop_template}"

server_script="${SCRIPT_DIR}/vcorp_create_debian_server.sh"
desktop_script="${SCRIPT_DIR}/vcorp_create_debian_desktop.sh"

# ============================================================
# FUNCIONS AUXILIARS
# ============================================================

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" >/dev/null 2>&1
}

create_template_if_missing() {
    local vm_name="$1"
    local script="$2"
    local template_type="$3"
    local template_env="$4"

    if vm_exists "$vm_name"; then
        log_ok "La plantilla ${vm_name} ja existeix. Es conserva."
        return 0
    fi

    log_info "Creant la plantilla Debian ${template_type}..."

    env "$template_env=$vm_name" bash "$script"

    if ! vm_exists "$vm_name"; then
        log_err "La plantilla ${vm_name} no s'ha registrat correctament."
        return 1
    fi

    log_ok "Plantilla ${vm_name} creada correctament."
}

# ============================================================
# EXECUCIO PRINCIPAL
# ============================================================

main() {

    log_info "Comprovant els scripts de desplegament..."

    if [[ ! -f "$server_script" || ! -f "$desktop_script" ]]; then
        log_err "Falta un dels scripts de creacio Debian."
        return 1
    fi

    log_info "Iniciant el desplegament de plantilles Debian..."

    create_template_if_missing \
        "$server_template" "$server_script" "Server" "DEBIAN_SERVER_TEMPLATE"

    create_template_if_missing \
        "$desktop_template" "$desktop_script" "Desktop" "DEBIAN_DESKTOP_TEMPLATE"

    log_ok "Les plantilles Debian estan disponibles."
}

main "$@"
