
# Este archivo define qué datos necesitamos introducir 
# para conectar Terraform con nuestro Proxmox, sin 
# necesidad de escribir las credenciales directamente 
# en el código principal.

variable "proxmox_api_url" {
  type        = string
  description = "Endpoint o URL de la API de Proxmox (ej: https://10.8.0.133:8006/api2/json)"
}

variable "proxmox_node" {
  type        = string
  description = "Nombre del nodo de Proxmox donde se creará la infraestructura (ej: pve01)"
  default     = "pve01"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Identificador del token de API de Proxmox (usuario@pam!nombre_token)"
  sensitive   = true # Oculta este valor en los logs de la consola por seguridad
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Clave secreta (secret) asociada al token de API de Proxmox"
  sensitive   = true # Oculta este valor en los logs de la consola por seguridad
}