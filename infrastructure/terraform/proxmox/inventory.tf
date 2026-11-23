# Inventari dinàmic d'Ansible per als serveis LXC gestionats per Terraform.
# Les adreces MAC es llegeixen directament de l'estat real dels recursos Proxmox; mai es copien a mà.
# - dhcp01: Terraform li assigna IP estàtica (10.8.0.137/26), per això exporta vcorp_ipv4_cidr i ansible_host.
# - dns01: interfície configurada per DHCP, sense IP fixa aquí; Kea li assigna 10.8.0.138 per reserva MAC.
locals {
  # Extreu la IP en format CIDR del contenidor dhcp01 (ex. "10.8.0.137/26") per reutilitzar-la
  dhcp01_cidr = proxmox_virtual_environment_container.dhcp01.initialization[0].ip_config[0].ipv4[0].address

  # Estructura jeràrquica YAML que es bolcarà com a inventari d'Ansible (proxmox_lxc.yml)
  ansible_inventory = {
    all = {
      children = {
        # Grup pare que agrupa tots els contenidors LXC creats a Proxmox
        proxmox_lxc = {
          children = {
            # Grup amb les metadades de xarxa de cada servei; el rol kea_dhcp el llegeix per crear reserves
            terraform_services = {
              hosts = {
                dhcp01 = {
                  hostname          = "dhcp01"
                  vcorp_mac_address = proxmox_virtual_environment_container.dhcp01.network_interface[0].mac_address
                  vcorp_network     = "privada"
                  vcorp_ipv4_cidr   = local.dhcp01_cidr
                  # Separa la IP de la màscara CIDR ("10.8.0.137/26" -> "10.8.0.137") per a la connexió SSH d'Ansible
                  ansible_host      = split("/", local.dhcp01_cidr)[0]
                }
                dns01 = {
                  hostname          = "dns01"
                  vcorp_mac_address = proxmox_virtual_environment_container.dns01.network_interface[0].mac_address
                  vcorp_network     = "privada"
                  # No es defineix ansible_host aquí; es resol via inventari estàtic (lab.yml) o DNS/reserva
                }
              }
            }
            # Grup específic per al playbook de desplegament del servidor Kea DHCPv4
            kea_dhcp = {
              hosts = {
                dhcp01 = {}
              }
            }
            # Grup específic per al playbook de desplegament del servidor DNS BIND9
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

# Genera automàticament el fitxer YAML d'inventari dins del directori d'Ansible
# cada vegada que s'executa terraform apply, garantint una única font de veritat (Single Source of Truth)
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../automation/ansible/inventories/proxmox_lxc.yml"
  content         = yamlencode(local.ansible_inventory) # Converteix l'objecte HCL a sintaxi YAML vàlida
  file_permission = "0644"                                # Permisos estàndard de lectura per a Ansible
}