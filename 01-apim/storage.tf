resource "azurerm_storage_account" "this" {
  name                            = local.storage_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  # Shared key stays on: azurerm_storage_table_entity needs it for seeding.
  shared_access_key_enabled = true
  tags                      = local.tags
}

resource "azurerm_storage_table" "customers" {
  name               = "customers"
  storage_account_id = azurerm_storage_account.this.id
}

locals {
  seed_customers = {
    c001 = { name = "Erika Musterfrau", email = "erika@example.com", city = "Köln" }
    c002 = { name = "Max Mustermann", email = "max@example.com", city = "Berlin" }
    c003 = { name = "Anna Schmidt", email = "anna@example.com", city = "München" }
    c004 = { name = "Jonas Weber", email = "jonas@example.com", city = "Hamburg" }
    # c005 intentionally has no city, to exercise the null-safe response mapping.
    c005 = { name = "Lea Fischer", email = "lea@example.com", city = null }
  }
}

resource "azurerm_storage_table_entity" "seed" {
  for_each = local.seed_customers

  storage_table_id = azurerm_storage_table.customers.id
  partition_key    = "customer"
  row_key          = each.key
  entity           = { for k, v in each.value : k => v if v != null }
}
