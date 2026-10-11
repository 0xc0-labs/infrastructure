# The default jurisdiction, not eu: an eu bucket answers only at the .eu.
# endpoint, and every resource naming it needs the jurisdiction too, which the
# provider does not carry through (cloudflare/terraform-provider-cloudflare#5144).
resource "cloudflare_r2_bucket" "main" {
  account_id = var.account_id
  name       = var.name
  location   = var.location

  lifecycle {
    # It holds the application's files. Only a literal is allowed: a
    # deliberate removal lifts it in that PR.
    prevent_destroy = true
  }
}

# The bucket's r2.dev URL, off: nothing of it is public there.
resource "cloudflare_r2_managed_domain" "main" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.main.name
  enabled     = false
}

data "cloudflare_zone" "main" {
  count = var.custom_domain == null ? 0 : 1

  filter = {
    name = var.custom_domain.zone_name
  }
}

# Cloudflare makes the hostname's DNS record and certificate itself. Neither
# this nor the managed domain can be imported: nothing is made by hand first.
resource "cloudflare_r2_custom_domain" "main" {
  count = var.custom_domain == null ? 0 : 1

  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.main.name
  domain      = var.custom_domain.hostname
  zone_id     = data.cloudflare_zone.main[0].zone_id
  enabled     = true
  min_tls     = "1.2"

  lifecycle {
    precondition {
      condition     = data.cloudflare_zone.main[0].account.id == var.account_id
      error_message = "The custom domain's zone must be in the bucket's own account."
    }
  }
}
