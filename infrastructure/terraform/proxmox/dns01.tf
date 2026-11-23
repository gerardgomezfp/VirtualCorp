# Contenidor LXC del servidor DNS (BIND9) de la Delegació 8 de VirtualCorp.
# L'adreça IP (10.8.0.138) i la configuració de xarxa les assigna Kea DHCPv4 per reserva:
# aquí NO es defineix IP estàtica ni gateway manual, tot entra via DHCP.
#
# MAC fixa i administrada localment: 02:00:00:00:00:8A
#   - L'últim octet de la IP (138) en hexadecimal és 0x8A (8*16 + 10 = 138),
#     facilitant la traçabilitat entre reserva DHCP, inventari i contenidor.
#   - El prefix 02 (bit U/L = 1 al primer octet) indica una MAC administrada localment,
#     evitant col·lisions amb MAC de fabricants reals com VirtualBox (08:00:27) o Proxmox (BC:24:11).
resource "proxmox_virtual_environment_container" "dns01" {
  # Node de Proxmox VE on es desplega el contenidor (p. ex. pve01)
  node_name = var.proxmox_node

  # Identificador únic de contenidor dins de Proxmox (201 = dhcp01, 202 = dns01)
  vm_id = 202

  # Contenidor no privilegiat per reforçar l'aïllament de seguretat respecte al host Proxmox
  unprivileged = true

  # S'engega automàticament en crear/aplicar i arrenca amb el node Proxmox
  started       = true
  start_on_boot = true

  # Sistema base lleuger amb plantilla estàndard de Debian 13 per executar BIND9
  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }

  # Assignació de CPU ajustada al rol DNS autoritari/recursiu intern
  cpu {
    cores = 1
  }

  # 512 MB de RAM dedicats, suficients per a BIND9 i les seves zones/cau en aquest entorn
  memory {
    dedicated = 512
  }

  # Disc virtual de 4 GB sobre local-lvm per al SO, paquets BIND9 i fitxers de zona
  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  # Paràmetres inicials de cloud-init / configuració del contenidor
  initialization {
    hostname = "dns01"

    user_account {
      # Reutilitza les mateixes claus SSH d'administració que dhcp01 per mantenir l'accés unificat d'Ansible
      keys = proxmox_virtual_environment_container.dhcp01.initialization[0].user_account[0].keys
    }

    ip_config {
      ipv4 {
        # Sol·licita la IP per DHCP (que Kea entregarà per reserva MAC a 10.8.0.138)
        address = "dhcp"
      }
    }
  }

  # Interfície de xarxa virtual connectada al bridge vmbr0 amb la MAC reservada a Kea
  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = "02:00:00:00:00:8A"
  }
}