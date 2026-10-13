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

variable "sending_records" {
  description = "The records the provider's DNS page asks for to send, besides DKIM, as it shows them: name relative to zone_name (send for send.0xc0.cc), type and content. Never proxied."
  type = list(object({
    name    = string
    type    = string
    content = string
  }))

  validation {
    condition = alltrue([
      for r in var.sending_records :
      contains(["CNAME", "TXT"], r.type) && can(regex("^[a-z0-9_-]+(\\.[a-z0-9_-]+)*$", r.name)) && r.name != "_dmarc" && !endswith(r.name, "_domainkey")
    ])
    error_message = "Each sending record is a CNAME or a TXT on a name under zone_name, neither _dmarc nor a DKIM selector: those have inputs of their own."
  }

  validation {
    condition     = length(distinct([for r in var.sending_records : "${r.type} ${r.name}"])) == length(var.sending_records)
    error_message = "Two sending records share a name and a type."
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

variable "report_domains" {
  description = "Domains whose DMARC reports (rua) come to an address on this one: each gets the record that authorizes it to, as external reporting requires (RFC 7489, 7.1)."
  type        = list(string)
  default     = []
}
