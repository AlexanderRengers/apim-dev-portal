resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  apim_name    = "apim-devportal-poc-${random_string.suffix.result}"
  storage_name = "stdevportal${random_string.suffix.result}"

  tags = {
    project = "apim-dev-portal-poc"
    owner   = var.publisher_email
  }

  # operationId aus der OpenAPI-Datei -> Policy-Datei
  operation_policies = {
    listCustomers   = "list-customers.xml"
    getCustomer     = "get-customer.xml"
    createCustomer  = "create-customer.xml"
    replaceCustomer = "replace-customer.xml"
    deleteCustomer  = "delete-customer.xml"
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
