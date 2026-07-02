resource "azurerm_key_vault" "main" {
  name                      = substr("kv-${var.prefix}-${random_string.sa_suffix.result}", 0, 24)
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled  = false
  tags                      = local.tags
}

# Espera a que propague el RBAC de data-plane antes de escribir secretos
resource "time_sleep" "kv_rbac" {
  depends_on      = [azurerm_role_assignment.tf_kv_officer]
  create_duration = "120s"
}

resource "azurerm_key_vault_secret" "rcon_password" {
  name         = "rcon-password"
  value        = random_password.rcon.result
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.kv_rbac]
}

resource "azurerm_key_vault_secret" "backup_sas" {
  name         = "backup-sas-token"
  value        = data.azurerm_storage_account_sas.backup_ro.sas
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.kv_rbac]
}
