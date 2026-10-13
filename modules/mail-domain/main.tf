data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

locals {
  # 3600 is what the two records made in the dashboard carry: an import keeps
  # them as they are (#219).
  ttl     = 3600
  comment = "OpenTofu: infrastructure, modules/mail-domain"
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

# Never the apex, whose MX and SPF are Email Routing's (README.md).
resource "cloudflare_dns_record" "sending" {
  for_each = { for r in var.sending_records : "${r.type} ${r.name}" => r }

  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${each.value.name}.${var.zone_name}"
  type    = each.value.type
  content = each.value.content
  proxied = false
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

resource "cloudflare_dns_record" "report_authorization" {
  for_each = toset(var.report_domains)

  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${each.key}._report._dmarc.${var.zone_name}"
  type    = "TXT"
  content = "v=DMARC1"
  ttl     = local.ttl
  comment = local.comment
}
