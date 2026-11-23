# Bloc de configuració general i requisits de proveïdors
terraform {
  required_version = ">= 1.5.0" # Exigeix una versió mínima de Terraform instal·lada per compatibilitat sintàctica
  required_providers {
    # Proveïdor local per generar fitxers al controlador (com l'inventari dinàmic d'Ansible)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5" # Permet actualitzacions menors dins de la branca 2.x
    }
    # Proveïdor de Proxmox VE per gestionar contenidors LXC i recursos via API
    proxmox = {
      source  = "bpg/proxmox" # Proveïdor de Proxmox desenvolupat per bpg
      version = "~> 0.112.0"  # Fixa la sèrie de versions 0.112.x per estabilitat
    }
  }
}

# Configuració de la connexió amb l'hipervisor Proxmox
provider "proxmox" {
  endpoint  = var.proxmox_api_url                                           # Utilitza la URL de la variable definida a variables.tf
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" # Combina l'ID i el secret del token de manera segura
  insecure  = true                                                          # Permet acceptar certificats SSL autosignats del laboratori
}

# Contenidor LXC dhcp01 per al servidor Kea DHCPv4 de la Delegació 8 (10.8.0.137/26).
# A diferència de dns01, dhcp01 porta IP estàtica perquè és el primer servei de xarxa
# que ha d'estar operatiu abans de poder repartir adreces o reserves per DHCP.
resource "proxmox_virtual_environment_container" "dhcp01" {
  node_name    = var.proxmox_node # Node de Proxmox on es desplega (p. ex. pve01)
  vm_id        = 201              # Identificador únic del contenidor a Proxmox (201 = dhcp01)
  unprivileged = true             # Contenidor no privilegiat per reforçar l'aïllament de seguretat
  started      = true             # Arrenca el contenidor automàticament després de crear-lo

  # Plantilla base lleugera de Debian 13 per executar el servei kea-dhcp4-server
  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst" # Ajusta el nom exacte de la plantilla si difereix
    type             = "debian"
  }

  # Recursos de còmput i emmagatzematge ajustats al servidor DHCP
  cpu {
    cores = 1
  }

  memory {
    dedicated = 512 # 512 MB de RAM dedicats
  }

  disk {
    datastore_id = "local-lvm"
    size         = 6 # 6 GB de disc per al sistema base, paquets Kea i fitxers de leases
  }

  # Configuració inicial del contenidor (hostname, accés SSH i xarxa estàtica)
  initialization {
    hostname = "dhcp01"

    user_account {
      # Claus públiques SSH autoritzades: administració (Ansible/sysadmin) i auditoria
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFz5ICUA6x2Hq3R9jV6M9w7qqLCd358whyp3l+P35sSs vcorp_sysadmin",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK313FBREF929KceJ7V98F8Hwywf+dgXuXtiCkuCMMSe vcorp_auditor@virtualcorp"
      ]
    }

    ip_config {
      ipv4 {
        # IP fixa dins la subxarxa privada de servidors (10.8.0.128/26); s'usa .137 per no solapar amb intrasrv (.136)
        address = "10.8.0.137/26"
        # Porta d'enllaç de la LAN privada cap al router mikrotik0 (R0)
        gateway = "10.8.0.129"
      }
    }
  }

  # Interfície de xarxa virtual connectada al bridge vmbr0 de Proxmox
  network_interface {
    name   = "eth0"
    bridge = "vmbr0" # Bridge intern connectat a la xarxa privada de la Delegació 8
  }
}