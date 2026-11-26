variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "name" {
  description = "Name of the application. The group and the policy are named after it."
  type        = string
}

variable "domain" {
  description = "Hostname the application protects."
  type        = string
}

variable "operator_emails" {
  description = "The operator's emails: the group's seed, and let in by the policy whatever the group holds."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(nonsensitive(var.operator_emails)) > 0
    error_message = "operator_emails: at least one, Cloudflare refuses a group with no members."
  }
}

variable "identity_provider_id" {
  description = "ID of the account's one-time PIN identity provider, the only login offered."
  type        = string
}

variable "session_duration" {
  description = "How long a login lasts."
  type        = string
  default     = "24h"
}

variable "bypass_paths" {
  description = "Paths on the hostname, and what is under them, reached without a login. Anyone can reach them: each must authenticate its callers itself."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.bypass_paths : startswith(p, "/")])
    error_message = "bypass_paths: each path starts with a slash."
  }
}
