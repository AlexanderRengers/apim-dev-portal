locals {
  # dev (workspace "default") keeps the original name; other stages get a suffix, e.g. "-prod".
  app_display_name = terraform.workspace == "default" ? "apim-dev-portal-poc-portal" : "apim-dev-portal-poc-portal-${terraform.workspace}"
}

resource "azuread_application" "portal" {
  display_name     = local.app_display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  # MSAL-2 in the developer portal needs an SPA redirect URI, not a web redirect URI.
  single_page_application {
    redirect_uris = ["${var.developer_portal_url}/signin"]
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read (delegated)
      type = "Scope"
    }
  }

  depends_on = [terraform_data.portal_preflight]
}

# Without a service principal, sign-in of tenant users fails with an AADSTS error.
resource "azuread_service_principal" "portal" {
  client_id                    = azuread_application.portal.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

# Rotation: tofu -chdir=02-portal apply -replace=time_offset.secret_expiry
resource "time_offset" "secret_expiry" {
  offset_days = var.secret_lifetime_days
}

resource "azuread_application_password" "portal" {
  application_id = azuread_application.portal.id
  display_name   = "apim-portal"
  end_date       = time_offset.secret_expiry.rfc3339
}

# Wait briefly until the new secret has propagated in Entra.
resource "time_sleep" "secret_propagation" {
  create_duration = "30s"
  triggers = {
    key_id = azuread_application_password.portal.key_id
  }
}
