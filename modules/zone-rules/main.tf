data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# The whole of each phase (README.md). The dashboard names its rulesets
# "default": with that name, one it made imports without being replaced.
resource "cloudflare_ruleset" "cache_settings" {
  count = length(var.cache_rules) > 0 ? 1 : 0

  zone_id = data.cloudflare_zone.main.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [for r in var.cache_rules : {
    ref         = r.ref
    description = r.description
    expression  = r.expression
    action      = "set_cache_settings"
    enabled     = true
    action_parameters = {
      cache       = true
      edge_ttl    = { mode = "override_origin", default = r.edge_ttl }
      browser_ttl = { mode = "override_origin", default = r.browser_ttl }
    }
  }]
}

resource "cloudflare_ruleset" "response_headers" {
  count = length(var.response_headers) > 0 ? 1 : 0

  zone_id = data.cloudflare_zone.main.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_response_headers_transform"

  rules = [for r in var.response_headers : {
    ref         = r.ref
    description = r.description
    expression  = r.expression
    action      = "rewrite"
    enabled     = true
    action_parameters = {
      headers = { for name, value in r.set : name => { operation = "set", value = value } }
    }
  }]
}
