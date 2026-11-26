variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "team_name" {
  description = "Zero Trust team name: the issuer lives at <team_name>.cloudflareaccess.com."
  type        = string
}

variable "name" {
  description = "Name of the application, as the Access launcher shows it."
  type        = string
}

variable "redirect_uris" {
  description = "Where the tool receives the login: its callback, and a CLI's local one."
  type        = list(string)

  validation {
    condition     = length(var.redirect_uris) > 0
    error_message = "redirect_uris: at least one."
  }
}

variable "policy_id" {
  description = "ID of the reusable Access policy that decides who signs in: the one that admits the operator and the admins team."
  type        = string
}
