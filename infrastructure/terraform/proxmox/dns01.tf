# Contenedor DNS de VirtualCorp. La IP (10.8.0.138) la asigna Kea por reserva:
# aquí NO hay dirección ni gateway estáticos, solo DHCP.
#
# MAC fija y local: 02:00:00:00:00:8A
#   - 138 (último octeto de la IP) en hexadecimal = 0x8A (8*16 + 10)
#   - el prefijo 02 marca una MAC administrada localmente; las MAC reales del
#     laboratorio empiezan por 08:00:27 (VirtualBox) o BC:24:11 (Proxmox)
resource "proxmox_virtual_environment_container" "dns01" {
  node_name     = var.proxmox_node
  vm_id         = 202
  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  initialization {
    hostname = "dns01"

    user_account {
      # Mismas claves de administración que dhcp01
      keys = proxmox_virtual_environment_container.dhcp01.initialization[0].user_account[0].keys
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = "02:00:00:00:00:8A"
  }
}
