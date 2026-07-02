output "server_address" {
  description = "Direccion para conectarse (Java: :25565, Bedrock: :19132)"
  value       = azurerm_public_ip.main.fqdn
}

output "public_ip" {
  description = "IP publica del bootstrap (cambia en cada ciclo start/stop; usa siempre server_address)"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_name" {
  description = "Nombre de la VM"
  value       = azurerm_linux_virtual_machine.main.name
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "storage_account" {
  description = "Storage Account de backups"
  value       = azurerm_storage_account.backup.name
}

output "backup_container" {
  value = azurerm_storage_container.backup.name
}

output "ssh_command" {
  description = "Comando SSH para administrar la VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.fqdn}"
}

output "start_command" {
  description = "OJO: 'az vm start' a secas arranca SIN IP publica. Enciende siempre con scripts/start.ps1 o el boton web."
  value       = "scripts/start.ps1  (o el boton web de start_url)"
}

output "stop_command" {
  description = "Apagar la VM manualmente"
  value       = "az vm deallocate -g ${azurerm_resource_group.main.name} -n ${azurerm_linux_virtual_machine.main.name}"
}

output "start_function_url" {
  description = "URL base de la Function de arranque (si enable_start_function=true)"
  value       = var.enable_start_function ? "https://${azurerm_linux_function_app.start[0].default_hostname}/api/start" : "no habilitada"
}

output "start_url" {
  description = "URL completa (con clave) del boton de encendido — la que se comparte con los amigos"
  value       = var.enable_start_function ? "https://${azurerm_linux_function_app.start[0].default_hostname}/api/start?code=${data.azurerm_function_app_host_keys.start[0].default_function_key}" : "no habilitada"
  sensitive   = true
}

output "backup_sas_token" {
  description = "SAS de solo lectura para descargar backups desde el PC"
  value       = data.azurerm_storage_account_sas.backup_ro.sas
  sensitive   = true
}
