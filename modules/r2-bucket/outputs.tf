output "name" {
  description = "The bucket's name."
  value       = cloudflare_r2_bucket.main.name
}

output "endpoint" {
  description = "The account's S3 endpoint, where the application reaches the bucket with its token."
  value       = "https://${var.account_id}.r2.cloudflarestorage.com"
}

output "public_url" {
  description = "Where the bucket's files are served, or null for a private bucket."
  value       = var.custom_domain == null ? null : "https://${var.custom_domain.hostname}"
}
