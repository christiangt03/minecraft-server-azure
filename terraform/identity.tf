# La VM puede apagarse a si misma (auto-deallocate por inactividad)
resource "azurerm_role_assignment" "vm_self_deallocate" {
  scope                = azurerm_linux_virtual_machine.main.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_virtual_machine.main.identity[0].principal_id
}

# La VM puede subir backups al blob sin claves (usa su Managed Identity)
resource "azurerm_role_assignment" "vm_blob_writer" {
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.main.identity[0].principal_id
}

# El usuario que ejecuta Terraform puede escribir secretos en Key Vault (data-plane)
resource "azurerm_role_assignment" "tf_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
