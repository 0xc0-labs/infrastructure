variable "zone_name" {
  description = "Domain the mail is sent as, a zone in Cloudflare, e.g. 0xc0.cc."
  type        = string
}

variable "dkim" {
  description = "The sending provider's DKIM key: its selector (resend for Resend) and the TXT value it shows for it, p=<public key>."
  type = object({
    selector = string
    value    = string
  })

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.dkim.selector))
    error_message = "dkim.selector is lowercase letters, digits and hyphens."
  }

  validation {
    condition     = can(regex("^(v=DKIM1; ?)?(k=rsa; ?)?p=[A-Za-z0-9+/]+={0,2}$", var.dkim.value))
    error_message = "dkim.value is the TXT value the provider shows, p=<base64 public key>, optionally after v=DKIM1; and k=rsa;."
  }
}

variable "mail_from" {
  description = "The MAIL FROM domain, a subdomain of zone_name (send for send.0xc0.cc), and the Amazon SES region the provider sends from (Resend's, e.g. eu-west-1), whose feedback MX it points at."
  type = object({
    subdomain = string
    region    = string
  })

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.mail_from.subdomain)) && can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.mail_from.region))
    error_message = "mail_from.subdomain is one label, and mail_from.region an AWS region such as eu-west-1."
  }
}

variable "dmarc" {
  description = "The domain's DMARC policy: p and sp, for the domain and its subdomains (none, quarantine or reject); adkim and aspf, the alignment (r relaxed, s strict); and rua, the address aggregate reports go to."
  type = object({
    p     = string
    sp    = string
    adkim = string
    aspf  = string
    rua   = string
  })

  validation {
    condition     = alltrue([for v in [var.dmarc.p, var.dmarc.sp] : contains(["none", "quarantine", "reject"], v)])
    error_message = "dmarc.p and dmarc.sp are none, quarantine or reject."
  }

  validation {
    condition     = alltrue([for v in [var.dmarc.adkim, var.dmarc.aspf] : contains(["r", "s"], v)])
    error_message = "dmarc.adkim and dmarc.aspf are r or s."
  }

  validation {
    condition     = can(regex("^[^@ ;]+@[^@ ;]+$", var.dmarc.rua))
    error_message = "dmarc.rua is one address, without mailto:."
  }
}
