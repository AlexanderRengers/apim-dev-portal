variable "state_passphrase" {
  type        = string
  description = "Passphrase für die OpenTofu-State-Verschlüsselung (über TF_VAR_state_passphrase, mindestens 16 Zeichen)."
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase muss mindestens 16 Zeichen lang sein."
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID, in der alles angelegt wird."
}

variable "location" {
  type        = string
  description = "Azure-Region."
  default     = "swedencentral"
}

variable "resource_group_name" {
  type        = string
  description = "Name der Resource Group für den PoC."
  default     = "apim-dev-portal-poc"
}

variable "publisher_name" {
  type        = string
  description = "Publisher-Name der APIM-Instanz."
  default     = "APIM Dev Portal PoC"
}

variable "publisher_email" {
  type        = string
  description = "Publisher-E-Mail der APIM-Instanz."
}
