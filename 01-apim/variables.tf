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
  description = "Azure subscription ID to deploy into."
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "swedencentral"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group for the PoC."
  default     = "apim-dev-portal-poc"
}

variable "publisher_name" {
  type        = string
  description = "Publisher name of the APIM instance."
  default     = "APIM Dev Portal PoC"
}

variable "publisher_email" {
  type        = string
  description = "Publisher email of the APIM instance."
}
