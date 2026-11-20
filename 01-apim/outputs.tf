output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "apim_name" {
  value = azurerm_api_management.this.name
}

output "gateway_url" {
  value = azurerm_api_management.this.gateway_url
}

output "developer_portal_url" {
  value = azurerm_api_management.this.developer_portal_url
}

output "smoke_subscription_key" {
  value     = azurerm_api_management_subscription.smoke.primary_key
  sensitive = true
}
