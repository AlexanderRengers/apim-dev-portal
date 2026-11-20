output "developer_portal_url" {
  value = var.developer_portal_url
}

output "entra_client_id" {
  value = azuread_application.portal.client_id
}

output "secret_expires_at" {
  value = time_offset.secret_expiry.rfc3339
}
