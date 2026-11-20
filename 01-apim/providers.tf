provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    api_management {
      # Allows rebuilding under the same name without the 48h soft-delete lock.
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
    resource_group {
      # Allows teardown even if Azure created resources in the RG outside of the state.
      prevent_deletion_if_contains_resources = false
    }
  }
}
