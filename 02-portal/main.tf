data "azurerm_api_management" "this" {
  name                = var.apim_name
  resource_group_name = var.resource_group_name
}

data "azuread_client_config" "current" {}

# Fails if the developer portal has no content yet (the manual admin click is missing).
resource "terraform_data" "portal_preflight" {
  triggers_replace = data.azurerm_api_management.this.id

  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/portal-preflight.sh ${data.azurerm_api_management.this.id}"
  }
}
