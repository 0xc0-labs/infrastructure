variable "zone_name" {
  description = "Zone the settings are for, e.g. 0xc0.cc."
  type        = string
}

variable "min_tls_version" {
  description = "The lowest TLS version Cloudflare's edge accepts for the zone's proxied names. 1.0 and 1.1 are deprecated (RFC 8996)."
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.2", "1.3"], var.min_tls_version)
    error_message = "min_tls_version is 1.2 or 1.3: 1.0 and 1.1 are deprecated (RFC 8996)."
  }
}
