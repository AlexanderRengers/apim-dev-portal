resource "azurerm_api_management_identity_provider_aad" "this" {
  api_management_name = data.azurerm_api_management.this.name
  resource_group_name = data.azurerm_api_management.this.resource_group_name
  client_id           = azuread_application.portal.client_id
  client_secret       = azuread_application_password.portal.value
  client_library      = "MSAL-2"
  signin_tenant       = var.tenant_id
  allowed_tenants     = [var.tenant_id]

  depends_on = [time_sleep.secret_propagation]
}

# Portal-Inhalte als Code: 02-portal/content/ (data.json + media/) entsteht mit 'make portal-capture'.
# Ändert sich der Snapshot, werden Inhalte und Medien der Instanz ERSETZT (nicht zusammengeführt).
# Fehlt der Ordner, bleibt der Inhalt der Instanz unangetastet.
locals {
  content_dir   = "${path.module}/content"
  content_files = sort(fileset(local.content_dir, "**"))
  content_hash  = sha256(join(",", [for f in local.content_files : "${f}=${filesha256("${local.content_dir}/${f}")}"]))
}

resource "terraform_data" "portal_content" {
  count            = length(local.content_files) > 0 ? 1 : 0
  triggers_replace = [data.azurerm_api_management.this.id, local.content_hash]

  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/portal-content.sh apply ${data.azurerm_api_management.this.id} ${local.content_dir}"
  }

  depends_on = [terraform_data.portal_preflight]
}

# Veröffentlicht das Portal neu, sobald sich eine Eingabe der Anmeldung oder der Portal-Inhalt ändert.
# Secret-Werte gehen nie in den Hash ein, nur die key_id.
resource "terraform_data" "portal_publish" {
  triggers_replace = sha256(jsonencode({
    client_id = azuread_application.portal.client_id
    key_id    = azuread_application_password.portal.key_id
    tenant_id = var.tenant_id
    content   = local.content_hash
  }))

  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/portal-publish.sh ${data.azurerm_api_management.this.id}"
  }

  depends_on = [azurerm_api_management_identity_provider_aad.this, terraform_data.portal_content]
}
