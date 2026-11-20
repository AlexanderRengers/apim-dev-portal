resource "azurerm_api_management_product" "self_service" {
  product_id            = "self-service-customer-portal"
  display_name          = "Self-Service Customer Portal"
  description           = "Self-service access to the Customers API (PoC, demo data). Subscription without approval, 60 calls per minute."
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  published             = true
  subscription_required = true
  approval_required     = false
  subscriptions_limit   = 1
}

resource "azurerm_api_management_product_api" "customers" {
  api_name            = azurerm_api_management_api.customers.name
  product_id          = azurerm_api_management_product.self_service.product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
}

# "developers" is a built-in APIM group, not an Entra group.
data "azurerm_api_management_group" "developers" {
  name                = "developers"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_api_management_product_group" "developers" {
  product_id          = azurerm_api_management_product.self_service.product_id
  group_name          = data.azurerm_api_management_group.developers.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_api_management_product_policy" "self_service" {
  product_id          = azurerm_api_management_product.self_service.product_id
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = file("${path.module}/policies/product.xml")
}

resource "azurerm_api_management_subscription" "smoke" {
  display_name        = "smoke-test"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  product_id          = azurerm_api_management_product.self_service.id
  state               = "active"
  # Azure turns off tracing on subscriptions by itself. Without this line every plan reports drift.
  allow_tracing = false
}
