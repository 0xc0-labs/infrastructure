data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# Every zone has every setting already: creating this sets it, and removing it
# leaves it as it is, not as Cloudflare's default.
resource "cloudflare_zone_setting" "main" {
  zone_id    = data.cloudflare_zone.main.zone_id
  setting_id = "min_tls_version"
  value      = var.min_tls_version
}
