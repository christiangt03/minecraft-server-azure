# ---------------------------------------------------------------------------
# Boton "Encender servidor" bajo demanda (Azure Function, plan Consumo ~gratis)
# Se crea solo si enable_start_function = true (fase 2, tras validar el core).
# ---------------------------------------------------------------------------

data "archive_file" "start_fn" {
  count       = var.enable_start_function ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../scripts/start-vm"
  output_path = "${path.module}/.build/start-vm.zip"
}

resource "azurerm_storage_container" "deploy" {
  count                 = var.enable_start_function ? 1 : 0
  name                  = "functiondeploy"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "start_fn_zip" {
  count                  = var.enable_start_function ? 1 : 0
  name                   = "start-vm-${data.archive_file.start_fn[0].output_md5}.zip"
  storage_account_name   = azurerm_storage_account.backup.name
  storage_container_name = azurerm_storage_container.deploy[0].name
  type                   = "Block"
  source                 = data.archive_file.start_fn[0].output_path
}

resource "azurerm_service_plan" "fn" {
  count               = var.enable_start_function ? 1 : 0
  name                = "asp-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.function_location # Y1 no disponible en spaincentral
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.tags
}

resource "azurerm_linux_function_app" "start" {
  count               = var.enable_start_function ? 1 : 0
  name                = "fn-${local.name}-${random_string.sa_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.function_location
  service_plan_id     = azurerm_service_plan.fn[0].id

  storage_account_name       = azurerm_storage_account.backup.name
  storage_account_access_key = azurerm_storage_account.backup.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
    cors {
      allowed_origins = ["*"]
    }
  }

  app_settings = {
    WEBSITE_RUN_FROM_PACKAGE = "${azurerm_storage_blob.start_fn_zip[0].url}${data.azurerm_storage_account_sas.backup_ro.sas}"
    SUBSCRIPTION_ID          = var.subscription_id
    RESOURCE_GROUP           = azurerm_resource_group.main.name
    VM_NAME                  = azurerm_linux_virtual_machine.main.name
    LOCATION                 = azurerm_resource_group.main.location
    NIC_NAME                 = azurerm_network_interface.main.name
    PIP_NAME                 = "pip-${local.name}" # mismo nombre que crea Terraform (mismo resource ID)
    DNS_LABEL                = var.dns_label
  }

  tags = local.tags
}

# La Function puede arrancar la VM
resource "azurerm_role_assignment" "fn_start_vm" {
  count                = var.enable_start_function ? 1 : 0
  scope                = azurerm_linux_virtual_machine.main.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_function_app.start[0].identity[0].principal_id
}

# La Function puede crear/borrar la IP publica y tocar la NIC (IP bajo demanda)
resource "azurerm_role_assignment" "fn_network" {
  count                = var.enable_start_function ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_linux_function_app.start[0].identity[0].principal_id
}

# Claves del host: para construir la URL de cleanup (webhook de la alerta) y la de start
data "azurerm_function_app_host_keys" "start" {
  count               = var.enable_start_function ? 1 : 0
  name                = azurerm_linux_function_app.start[0].name
  resource_group_name = azurerm_resource_group.main.name
}
