output "onetimepin_identity_provider_id" {
  description = "ID of the one-time PIN identity provider, the login the Access applications offer."
  value       = cloudflare_zero_trust_access_identity_provider.onetimepin.id
}
