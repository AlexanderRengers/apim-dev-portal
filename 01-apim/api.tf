resource "azurerm_api_management_api" "customers" {
  name         = "customers"
  display_name = "Customers API"
  # Same text as info.description in the OpenAPI file; APIM copies it on import, so it must be set here too.
  description           = "Simple CRUD API for customers (PoC, demo data). APIM talks directly to Azure Table Storage."
  resource_group_name   = azurerm_resource_group.this.name
  api_management_name   = azurerm_api_management.this.name
  path                  = "crm"
  protocols             = ["https"]
  revision              = "1"
  subscription_required = true

  import {
    content_format = "openapi"
    content_value  = file("${path.module}/api/customers.openapi.yaml")
  }
}

resource "azurerm_api_management_api_policy" "customers" {
  api_name            = azurerm_api_management_api.customers.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name

  xml_content = templatefile("${path.module}/policies/api.xml.tftpl", {
    table_endpoint = trimsuffix(azurerm_storage_account.this.primary_table_endpoint, "/")
    portal_origin  = azurerm_api_management.this.developer_portal_url
  })

  depends_on = [time_sleep.rbac]
}

resource "azurerm_api_management_api_operation_policy" "ops" {
  for_each = local.operation_policies

  api_name            = azurerm_api_management_api.customers.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  operation_id        = each.key
  xml_content         = file("${path.module}/policies/${each.value}")

  depends_on = [azurerm_api_management_api_policy.customers]
}
