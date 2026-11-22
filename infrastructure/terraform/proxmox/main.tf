# Bloc de configuració general i requisits de proveïdors
terraform {
  required_version = ">= 1.5.0" # Exigeix una versió mínima de Terraform instal·lada
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    proxmox = {
      source  = "bpg/proxmox" # Proveïdor de Proxmox desenvolupat per bpg
      version = "~> 0.112.0"  # Fixa la sèrie de versions 0.112.x
    }
  }
}

# Configuració de la connexió amb l'hipervisor Proxmox
provider "proxmox" {
  endpoint  = var.proxmox_api_url                                           # Utilitza la URL de la variable definida a variables.tf
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" # Combina l'ID i el secret del token de manera segura
  insecure  = true                                                          # Permet acceptar certificats SSL autosignats
}

# Contenidor LXC dhcp01 per a Kea DHCPv4 a la Delegació 8 (10.8.0.137/26)
resource "proxmox_virtual_environment_container" "dhcp01" {
  node_name    = var.proxmox_node
  vm_id        = 201
  unprivileged = true
  started      = true

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst" # Ajusta el nom exacte de la plantilla si difereix
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
    size         = 6
  }

  initialization {
    hostname = "dhcp01"

    user_account {
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFz5ICUA6x2Hq3R9jV6M9w7qqLCd358whyp3l+P35sSs vcorp_sysadmin",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK313FBREF929KceJ7V98F8Hwywf+dgXuXtiCkuCMMSe vcorp_auditor@virtualcorp"
      ]
    }

    ip_config {
      ipv4 {
        address = "10.8.0.137/26"
        gateway = "10.8.0.129"
      }
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0" # O el bridge intern corresponent de la topologia
  }
}
