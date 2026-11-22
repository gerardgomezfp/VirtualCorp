# Inventario Ansible de los servicios LXC gestionados por Terraform.
# Las MAC se leen de los recursos Proxmox; no se copian a mano.
# dhcp01: Terraform configura IP estática, por eso lleva vcorp_ipv4_cidr y ansible_host.
# dns01: interfaz DHCP, sin IP aquí; Kea la asigna por reserva (10.8.0.138).
locals {
  dhcp01_cidr = proxmox_virtual_environment_container.dhcp01.initialization[0].ip_config[0].ipv4[0].address

  ansible_inventory = {
    all = {
      children = {
        proxmox_lxc = {
          children = {
            terraform_services = {
              hosts = {
                dhcp01 = {
                  hostname          = "dhcp01"
                  vcorp_mac_address = proxmox_virtual_environment_container.dhcp01.network_interface[0].mac_address
                  vcorp_network     = "privada"
                  vcorp_ipv4_cidr   = local.dhcp01_cidr
                  ansible_host      = split("/", local.dhcp01_cidr)[0]
                }
                dns01 = {
                  hostname          = "dns01"
                  vcorp_mac_address = proxmox_virtual_environment_container.dns01.network_interface[0].mac_address
                  vcorp_network     = "privada"
                }
              }
            }
            kea_dhcp = {
              hosts = {
                dhcp01 = {}
              }
            }
            bind_dns = {
              hosts = {
                dns01 = {}
              }
            }
          }
        }
      }
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../automation/ansible/inventories/proxmox_lxc.yml"
  content         = yamlencode(local.ansible_inventory)
  file_permission = "0644"
}
