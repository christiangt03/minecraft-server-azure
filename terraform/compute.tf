resource "random_password" "rcon" {
  length  = 24
  special = false
}

locals {
  cloud_init = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    admin_username   = var.admin_username
    rcon_password    = random_password.rcon.result
    rcon_port        = 25575
    storage_account  = azurerm_storage_account.backup.name
    backup_container = azurerm_storage_container.backup.name
    discord_webhook  = var.discord_webhook_url
    idle_minutes     = var.idle_minutes
    cpu_threshold    = var.cpu_threshold
    ram_threshold    = var.ram_threshold
    disk_threshold   = var.disk_threshold
    max_players      = var.mc_max_players
    server_name      = "${var.dns_label}.${var.location}.cloudapp.azure.com"
    rcon_py_b64      = base64encode(file("${path.module}/../scripts/rcon.py"))
    monitor_b64      = base64encode(file("${path.module}/../scripts/mc-monitor.sh"))
    backup_b64       = base64encode(file("${path.module}/../scripts/mc-backup.sh"))
    idlestop_b64     = base64encode(file("${path.module}/../scripts/mc-idle-stop.sh"))
    crashalert_b64   = base64encode(file("${path.module}/../scripts/mc-crash-alert.sh"))
    setup_b64        = base64encode(file("${path.module}/../scripts/mc-setup.sh"))
  }))
}

resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-${local.name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.main.id]

  # Prioridad Spot (opcional). En Regular estos campos van a null.
  priority        = var.use_spot ? "Spot" : "Regular"
  eviction_policy = var.use_spot ? "Deallocate" : null
  max_bid_price   = var.use_spot ? -1 : null

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # HDD: ~1 EUR/mes menos que StandardSSD; suficiente para este uso
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = local.cloud_init

  tags = local.tags
}
