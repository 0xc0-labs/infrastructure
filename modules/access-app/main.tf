# The members are the operator's, edited in the dashboard: see the README.
# Cloudflare refuses a group with an empty include, hence the seed.
resource "cloudflare_zero_trust_access_group" "viewers" {
  account_id = var.account_id
  name       = "${var.name} viewers"
  include    = [for e in var.operator_emails : { email = { email = e } }]

  lifecycle {
    ignore_changes = [include]
  }
}

# The operator gets in even if the group is emptied.
resource "cloudflare_zero_trust_access_policy" "main" {
  account_id = var.account_id
  name       = "${var.name} viewers and operator"
  decision   = "allow"
  include = concat(
    [{ group = { id = cloudflare_zero_trust_access_group.viewers.id } }],
    [for e in var.operator_emails : { email = { email = e } }],
  )
}

resource "cloudflare_zero_trust_access_application" "main" {
  account_id                = var.account_id
  type                      = "self_hosted"
  name                      = var.name
  domain                    = var.domain
  session_duration          = var.session_duration
  allowed_idps              = [var.identity_provider_id]
  auto_redirect_to_identity = true
  policies                  = [{ id = cloudflare_zero_trust_access_policy.main.id, precedence = 1 }]
}
