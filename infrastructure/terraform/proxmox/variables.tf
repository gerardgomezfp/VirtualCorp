# Aquest fitxer defineix quines dades cal introduir per connectar
# Terraform amb Proxmox, sense escriure credencials directament
# al codi principal.

variable "proxmox_api_url" {
  type        = string
  description = "Endpoint o URL de l'API de Proxmox (p. ex.: https://10.8.0.133:8006/api2/json)"
}

variable "proxmox_node" {
  type        = string
  description = "Nom del node de Proxmox on es crearà la infraestructura (p. ex.: pve01)"
  default     = "pve01"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Identificador del token d'API de Proxmox (usuari@pam!nom_token)"
  sensitive   = true # Amaga aquest valor als registres de la consola per seguretat
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Clau secreta (secret) associada al token d'API de Proxmox"
  sensitive   = true # Amaga aquest valor als registres de la consola per seguretat
}
