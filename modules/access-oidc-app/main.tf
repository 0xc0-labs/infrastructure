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
    scopes        = ["openid", "email", "profile", "groups"]

    grant_types = concat(
      ["authorization_code"],
      var.public_client ? ["authorization_code_with_pkce"] : [],
      var.refresh_token_lifetime != null ? ["refresh_token"] : [],
    )

    # Null leaves the attribute unset, so the applications without a public
    # client plan no diff.
    allow_pkce_without_client_secret = var.public_client ? true : null
    access_token_lifetime            = var.access_token_lifetime
    refresh_token_options            = var.refresh_token_lifetime != null ? { lifetime = var.refresh_token_lifetime } : null
  }
}
