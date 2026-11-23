# Aquest fitxer defineix quines dades cal introduir per connectar
# Terraform amb Proxmox, sense escriure credencials directament
# al codi principal (per exemple, s'injecten via terraform.local.tfvars).

# URL base de l'API REST de Proxmox VE utilitzada pel provider per fer peticions
variable "proxmox_api_url" {
  type        = string # Tipus cadena de text per a l'adreça de l'API
  description = "Endpoint o URL de l'API de Proxmox (p. ex.: https://10.8.0.133:8006/api2/json)"
}

# Node destí del clúster/entorn Proxmox on es desplegaran els contenidors LXC
variable "proxmox_node" {
  type        = string # Tipus cadena de text per al nom del node
  description = "Nom del node de Proxmox on es crearà la infraestructura (p. ex.: pve01)"
  default     = "pve01" # Valor per defecte per evitar repetir-lo si no cal canviar de node
}

# Identificador del token d'API (s'evita usar contrasenya d'usuari directa i es pot revocar)
variable "proxmox_api_token_id" {
  type        = string # Tipus cadena de text amb el format realm!token
  description = "Identificador del token d'API de Proxmox (usuari@pam!nom_token)"
  sensitive   = true   # Amaga aquest valor als registres de la consola per seguretat
}

# Secret associat al token d'API per autenticar les operacions de Terraform contra Proxmox
variable "proxmox_api_token_secret" {
  type        = string # Tipus cadena de text per a la clau secreta del token
  description = "Clau secreta (secret) associada al token d'API de Proxmox"
  sensitive   = true   # Amaga aquest valor als registres de la consola i sortides de plan/apply
}