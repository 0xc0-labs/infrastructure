output "group_id" {
  description = "ID of the viewers' group."
  value       = cloudflare_zero_trust_access_group.viewers.id
}

output "application_id" {
  description = "ID of the Access application."
  value       = cloudflare_zero_trust_access_application.main.id
}
