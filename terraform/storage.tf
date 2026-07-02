resource "random_string" "sa_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "backup" {
  name                     = substr(lower("st${replace(var.prefix, "-", "")}${random_string.sa_suffix.result}"), 0, 24)
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Cool"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  tags = local.tags
}

resource "azurerm_storage_container" "backup" {
  name                  = "worldbackups"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

# Borra backups mas antiguos que backup_retention_days
resource "azurerm_storage_management_policy" "backup" {
  storage_account_id = azurerm_storage_account.backup.id

  rule {
    name    = "expire-old-backups"
    enabled = true
    filters {
      prefix_match = ["worldbackups/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.backup_retention_days
      }
    }
  }
}

# SAS de solo lectura para que el PC descargue los backups (1 año)
data "azurerm_storage_account_sas" "backup_ro" {
  connection_string = azurerm_storage_account.backup.primary_connection_string
  https_only        = true

  resource_types {
    service   = false
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = "2026-01-01T00:00:00Z"
  expiry = "2027-01-01T00:00:00Z"

  permissions {
    read    = true
    list    = true
    write   = false
    delete  = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}
