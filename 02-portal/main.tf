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

# Email/password registration off (Entra ID only). Set on the instance via the management API,
# because the azurerm setting lives on the APIM resource itself, which this root does not own.
resource "terraform_data" "portal_signup" {
  triggers_replace = [data.azurerm_api_management.this.id, var.signup_enabled]

  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/portal-signup.sh ${data.azurerm_api_management.this.id} ${var.signup_enabled}"
  }
}
