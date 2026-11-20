variable "state_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state encryption (via TF_VAR_state_passphrase, at least 16 characters)."
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters long."
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID (same as in 01-apim)."
}

variable "tenant_id" {
  type        = string
  description = "Entra tenant ID where the app registration is created; the only tenant allowed to sign in."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group of the APIM instance (from stage1.auto.tfvars)."
}

variable "apim_name" {
  type        = string
  description = "Name of the APIM instance (from stage1.auto.tfvars)."
}

variable "developer_portal_url" {
  type        = string
  description = "Developer portal URL (from stage1.auto.tfvars)."
}

variable "secret_lifetime_days" {
  type        = number
  description = "Client secret lifetime in days."
  default     = 90
}
