variable "subscription_id" {
  description = "ID de la suscripcion (Azure for Students)"
  type        = string
  default     = "ed313ee9-11b5-45d4-ac7c-6116fc894139"
}

variable "prefix" {
  description = "Prefijo de nombres de recursos"
  type        = string
  default     = "mcserver"
}

variable "env" {
  description = "Entorno (dev/prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Region de Azure"
  type        = string
  default     = "spaincentral"
}

variable "vm_size" {
  description = "Tamano de la VM"
  type        = string
  default     = "Standard_B2s"
}

variable "use_spot" {
  description = "Usar VM Spot (mas barata, puede ser desalojada). Suele estar limitada en cuentas de estudiante."
  type        = bool
  default     = false
}

variable "admin_username" {
  description = "Usuario administrador de la VM"
  type        = string
  default     = "azuremc"
}

variable "ssh_public_key_path" {
  description = "Ruta a la clave publica SSH para acceder a la VM"
  type        = string
  default     = "~/.ssh/mcserver.pub"
}

variable "allowed_ssh_cidr" {
  description = "CIDR permitido para SSH (tu IP publica /32). Redetectar con: curl -s https://api.ipify.org"
  type        = string
}

variable "dns_label" {
  description = "Etiqueta DNS para la IP publica -> {label}.spaincentral.cloudapp.azure.com (unica en la region)"
  type        = string
}

variable "alert_email" {
  description = "Email para las alertas de Azure"
  type        = string
}

variable "discord_webhook_url" {
  description = "Webhook de Discord para alertas de CPU/RAM/disco/crash (opcional). Vacio = desactivado."
  type        = string
  default     = ""
  sensitive   = true
}

variable "mc_max_players" {
  description = "Maximo de jugadores"
  type        = number
  default     = 10
}

variable "idle_minutes" {
  description = "Minutos sin jugadores antes de auto-apagar la VM"
  type        = number
  default     = 20
}

variable "backup_retention_days" {
  description = "Dias que se conservan los backups en el blob"
  type        = number
  default     = 30
}

variable "enable_start_function" {
  description = "Crear la Azure Function con boton web para que los amigos enciendan la VM bajo demanda"
  type        = bool
  default     = false
}

variable "function_location" {
  description = "Region para la Function de arranque. Y1 Linux no existe en spaincentral y la politica de la sub de estudiante solo permite: switzerlandnorth, francecentral, spaincentral, italynorth, norwayeast."
  type        = string
  default     = "francecentral"
}

variable "cpu_threshold" {
  description = "Umbral de alerta de CPU (%)"
  type        = number
  default     = 90
}

variable "ram_threshold" {
  description = "Umbral de alerta de RAM (%)"
  type        = number
  default     = 90
}

variable "disk_threshold" {
  description = "Umbral de alerta de disco (%)"
  type        = number
  default     = 85
}
