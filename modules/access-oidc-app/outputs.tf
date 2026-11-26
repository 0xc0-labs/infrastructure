output "client_id" {
  description = "The OIDC client ID the tool signs in with."
  value       = cloudflare_zero_trust_access_application.main.saas_app.client_id
}

output "client_secret" {
  description = "The OIDC client secret. Cloudflare returns it on creation only, so it lives in the state from then on."
  value       = cloudflare_zero_trust_access_application.main.saas_app.client_secret
  sensitive   = true
}

output "issuer" {
  description = "The OIDC issuer URL: Cloudflare's documented form, with the discovery document under /.well-known/openid-configuration."
  value       = "https://${var.team_name}.cloudflareaccess.com/cdn-cgi/access/sso/oidc/${cloudflare_zero_trust_access_application.main.saas_app.client_id}"
}
