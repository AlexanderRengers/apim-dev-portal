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
  description = "Azure Subscription ID (dieselbe wie in 01-apim)."
}

variable "tenant_id" {
  type        = string
  description = "Entra Tenant ID, in dem die App Registration angelegt wird und der als einziger Tenant zur Anmeldung zugelassen ist."
}

variable "resource_group_name" {
  type        = string
  description = "Resource Group der APIM-Instanz (aus stage1.auto.tfvars)."
}

variable "apim_name" {
  type        = string
  description = "Name der APIM-Instanz (aus stage1.auto.tfvars)."
}

variable "developer_portal_url" {
  type        = string
  description = "URL des Developer Portals (aus stage1.auto.tfvars)."
}

variable "secret_lifetime_days" {
  type        = number
  description = "Laufzeit des Client Secrets in Tagen."
  default     = 90
}
