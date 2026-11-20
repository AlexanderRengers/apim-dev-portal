resource "azuread_application" "portal" {
  display_name     = "apim-dev-portal-poc-portal"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  # MSAL-2 im Developer Portal braucht eine SPA-Redirect-URI, keine Web-Redirect-URI.
  single_page_application {
    redirect_uris = ["${var.developer_portal_url}/signin"]
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read (delegiert)
      type = "Scope"
    }
  }

  depends_on = [terraform_data.portal_preflight]
}

# Ohne Service Principal scheitert die Anmeldung der Tenant-Benutzer mit einem AADSTS-Fehler.
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

# Kurz warten, bis Entra das neue Secret überall kennt.
resource "time_sleep" "secret_propagation" {
  create_duration = "30s"
  triggers = {
    key_id = azuread_application_password.portal.key_id
  }
}
