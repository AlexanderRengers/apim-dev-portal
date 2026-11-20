provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    api_management {
      # Neuaufbau unter demselben Namen ohne 48h Soft-Delete-Sperre.
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
    resource_group {
      # Abbau auch, wenn Azure in der RG Ressourcen außerhalb des States angelegt hat.
      prevent_deletion_if_contains_resources = false
    }
  }
}
