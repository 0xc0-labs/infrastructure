# No allowed_idps: Cloudflare then offers every provider of the account, the
# one-time PIN and GitHub. auto_redirect_to_identity is left out too, since
# Cloudflare takes it with a single provider only.
resource "cloudflare_zero_trust_access_application" "main" {
  account_id = var.account_id
  type       = "saas"
  name       = var.name
  policies   = [{ id = var.policy_id, precedence = 1 }]

  saas_app = {
    auth_type     = "oidc"
    redirect_uris = var.redirect_uris
    grant_types   = ["authorization_code"]
    scopes        = ["openid", "email", "profile", "groups"]
  }
}
