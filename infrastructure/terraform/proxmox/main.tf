

# Bloque de configuración general y requisitos de proveedores
terraform {
  required_version = ">= 1.5.0" # Exige una versión mínima de Terraform instalada
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"     # Proveedor oficial de Proxmox desarrollado por bpg
      version = "~> 0.112.0"      # Fija la versión 0.112.x
    }
  }
}

# Configuración de la conexión con el hipervisor Proxmox
provider "proxmox" {
  endpoint  = var.proxmox_api_url                     # Utiliza la URL de la variable definida arriba
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" # Combina ID y Secret del token de forma segura
  insecure  = true                                    # Permite aceptar certificados SSL autofirmados
}

resource "proxmox_virtual_environment_container" "dhcp01" {
  node_name    = var.proxmox_node
  vm_id        = 201
  unprivileged = true
  started      = true

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst" # Ajusta el nombre exacto de tu plantilla si difiere
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
    name     = "eth0"
    bridge   = "vmbr0" # O el bridge interno correspondiente de tu topología
  }
}