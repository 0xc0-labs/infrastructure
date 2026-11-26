output "access_policy_id" {
  description = "ID of the policy that admits allowed_emails and the GitHub team: WARP enrollment's, reused by every application that admits the same people."
  value       = cloudflare_zero_trust_access_policy.main.id
}

output "onetimepin_identity_provider_id" {
  description = "ID of the one-time PIN identity provider, the login the Access applications offer."
  value       = cloudflare_zero_trust_access_identity_provider.onetimepin.id
}
