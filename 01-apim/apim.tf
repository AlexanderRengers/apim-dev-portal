resource "azurerm_api_management" "this" {
  name                = local.apim_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Developer_1"
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }

  # Sign-up aus = keine Registrierung mit E-Mail und Passwort, nur Anmeldung über Entra ID.
  # (azurerm 4.x hat dafür keine eigene Ressource, die Einstellung lebt im APIM-Block.)
  sign_up {
    enabled = false

    terms_of_service {
      enabled          = false
      consent_required = false
    }
  }

  timeouts {
    create = "2h"
    update = "2h"
    delete = "2h"
  }
}

resource "azurerm_role_assignment" "apim_table" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# Rollenzuweisungen wirken verzögert. Verkürzt die Phase mit 403, beseitigt sie aber nicht.
resource "time_sleep" "rbac" {
  create_duration = "120s"
  depends_on      = [azurerm_role_assignment.apim_table]
}
