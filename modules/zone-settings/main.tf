data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# Removing it leaves the zone's value as it is (README.md).
resource "cloudflare_zone_setting" "main" {
  zone_id    = data.cloudflare_zone.main.zone_id
  setting_id = "min_tls_version"
  value      = var.min_tls_version
}
