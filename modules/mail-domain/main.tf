data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

locals {
  # 3600 is what the two records made in the dashboard carry: an import keeps
  # them as they are (#219).
  ttl       = 3600
  comment   = "OpenTofu: infrastructure, modules/mail-domain"
  mail_from = "${var.mail_from.subdomain}.${var.zone_name}"
}

resource "cloudflare_dns_record" "dkim" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${var.dkim.selector}._domainkey.${var.zone_name}"
  type    = "TXT"
  content = var.dkim.value
  ttl     = local.ttl
  comment = local.comment
}

# A null key on every selector without a record of its own: nothing but the
# selectors published here signs as the domain.
resource "cloudflare_dns_record" "dkim_revoked" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "*._domainkey.${var.zone_name}"
  type    = "TXT"
  content = "v=DKIM1; p="
  ttl     = local.ttl
  comment = local.comment
}

# The apex's MX and SPF are Email Routing's, for the mail the domain receives:
# the bounces of the mail it sends go to a subdomain of their own.
resource "cloudflare_dns_record" "mail_from_mx" {
  zone_id  = data.cloudflare_zone.main.zone_id
  name     = local.mail_from
  type     = "MX"
  content  = "feedback-smtp.${var.mail_from.region}.amazonses.com"
  priority = 10
  ttl      = local.ttl
  comment  = local.comment
}

resource "cloudflare_dns_record" "mail_from_spf" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = local.mail_from
  type    = "TXT"
  content = "v=spf1 include:amazonses.com ~all"
  ttl     = local.ttl
  comment = local.comment
}

resource "cloudflare_dns_record" "dmarc" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_dmarc.${var.zone_name}"
  type    = "TXT"
  content = "v=DMARC1; p=${var.dmarc.p}; sp=${var.dmarc.sp}; adkim=${var.dmarc.adkim}; aspf=${var.dmarc.aspf}; rua=mailto:${var.dmarc.rua}"
  ttl     = local.ttl
  comment = local.comment
}
