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

variable "public_client" {
  description = "Also a public client: the authorization code flow with PKCE, which a CLI runs with its client ID alone, besides the one with the client secret."
  type        = bool
  default     = false
}

variable "access_token_lifetime" {
  description = "How long the OIDC access token lives, from 1m to 24h, in units m and h (\"1h\"). Null keeps Cloudflare's default."
  type        = string
  default     = null

  validation {
    condition = var.access_token_lifetime == null || (
      can(regex("^[0-9]+[mh]$", coalesce(var.access_token_lifetime, "0m"))) &&
      tonumber(regex("^[0-9]+", coalesce(var.access_token_lifetime, "0m"))) * (endswith(coalesce(var.access_token_lifetime, "0m"), "h") ? 60 : 1) >= 1 &&
      tonumber(regex("^[0-9]+", coalesce(var.access_token_lifetime, "0m"))) * (endswith(coalesce(var.access_token_lifetime, "0m"), "h") ? 60 : 1) <= 1440
    )
    error_message = "access_token_lifetime: a number and m or h, from 1m to 24h."
  }
}

variable "refresh_token_lifetime" {
  description = "How long the refresh token lives, in units m, h and d (\"1d\"). When set, the application also takes the refresh_token grant, so the tool renews its tokens without a browser login and Access checks the policy again at each refresh. Null issues no refresh token."
  type        = string
  default     = null

  validation {
    condition     = var.refresh_token_lifetime == null || can(regex("^[1-9][0-9]*[mhd]$", coalesce(var.refresh_token_lifetime, "0m")))
    error_message = "refresh_token_lifetime: a number and m, h or d."
  }
}

variable "policy_id" {
  description = "ID of the reusable Access policy that decides who signs in: the one that admits the operator and the admins team."
  type        = string
}
