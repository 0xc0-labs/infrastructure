variable "account_id" {
  description = "Cloudflare account holding the bucket."
  type        = string
}

variable "name" {
  description = "Bucket name, <namespace>-<purpose> (payload-media): the application's namespace, then what it keeps there."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "A bucket name is 3 to 63 lowercase letters, digits and hyphens, starting and ending with a letter or a digit."
  }
}

variable "location" {
  description = "Where Cloudflare places the bucket, best effort, and only when it is first created: weur is western Europe."
  type        = string
  default     = "weur"

  validation {
    condition     = contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], var.location)
    error_message = "location is one of apac, eeur, enam, weur, wnam or oc."
  }
}

variable "custom_domain" {
  description = "The hostname of ours the bucket's files are served at, read only and through Cloudflare's cache, and its zone, in the bucket's account. null keeps the bucket private: only a token reaches its files."
  type = object({
    hostname  = string
    zone_name = string
  })
  default = null

  validation {
    condition     = var.custom_domain == null || endswith(try(var.custom_domain.hostname, ""), ".${try(var.custom_domain.zone_name, "")}")
    error_message = "custom_domain.hostname must be a name under custom_domain.zone_name."
  }
}
