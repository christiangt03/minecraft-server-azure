resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "mcalerts"

  email_receiver {
    name          = "owner-email"
    email_address = var.alert_email
  }

  dynamic "webhook_receiver" {
    for_each = var.discord_webhook_url != "" ? [1] : []
    content {
      name        = "discord"
      service_uri = var.discord_webhook_url
    }
  }

  tags = local.tags
}

# Alerta: la VM fue apagada (deallocate) -> "el servidor se apago"
resource "azurerm_monitor_activity_log_alert" "deallocate" {
  name                = "alert-vm-deallocate-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [azurerm_linux_virtual_machine.main.id]
  description         = "La VM del servidor de Minecraft se ha apagado (deallocate)."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/deallocate/action"
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  tags = local.tags
}

# --- IP bajo demanda: al deallocate, un webhook llama a la Function 'cleanup'
# que desconecta y borra la IP publica (deja de cobrar mientras el server duerme).
resource "azurerm_monitor_action_group" "ip_cleanup" {
  count               = var.enable_start_function ? 1 : 0
  name                = "ag-ipcleanup-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ipcleanup"

  webhook_receiver {
    name                    = "fn-cleanup"
    service_uri             = "https://${azurerm_linux_function_app.start[0].default_hostname}/api/cleanup?code=${data.azurerm_function_app_host_keys.start[0].default_function_key}"
    use_common_alert_schema = false
  }

  tags = local.tags
}

resource "azurerm_monitor_activity_log_alert" "ip_cleanup" {
  count               = var.enable_start_function ? 1 : 0
  name                = "alert-ip-cleanup-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [azurerm_linux_virtual_machine.main.id]
  description         = "Dispara la Function cleanup para borrar la IP publica al apagarse la VM."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/deallocate/action"
    status         = "Succeeded"
  }

  action {
    action_group_id = azurerm_monitor_action_group.ip_cleanup[0].id
  }
  tags = local.tags
}

# Alerta: la VM recibio powerOff
resource "azurerm_monitor_activity_log_alert" "poweroff" {
  name                = "alert-vm-poweroff-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [azurerm_linux_virtual_machine.main.id]
  description         = "La VM del servidor de Minecraft recibio powerOff."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/powerOff/action"
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  tags = local.tags
}

# Alerta: problema de salud del recurso (caida inesperada del host / eviction Spot)
resource "azurerm_monitor_activity_log_alert" "resource_health" {
  name                = "alert-vm-health-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = "global"
  scopes              = [azurerm_linux_virtual_machine.main.id]
  description         = "Problema de Resource Health en la VM (caida inesperada / eviction)."

  criteria {
    category = "ResourceHealth"
    resource_health {
      current  = ["Degraded", "Unavailable"]
      previous = ["Available"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
  tags = local.tags
}
