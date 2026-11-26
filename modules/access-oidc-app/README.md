# access-oidc-app

Cloudflare Access as the OIDC identity provider of one tool: a SaaS
application of type OIDC.

- **One application**, `type = "saas"`, `auth_type = "oidc"`, with the
  `authorization_code` grant and the scopes `openid`, `email`, `profile` and
  `groups`. The tool signs in with its `client_id` and `client_secret` and
  reads the discovery document under the `issuer`.
- **A public client**, off by default: `public_client` adds the
  `authorization_code_with_pkce` grant and sets
  `allow_pkce_without_client_secret`, so a CLI signs in with the client ID
  alone while a server-side tool keeps using the secret.
- **Who gets in** is `policy_id`, a policy the caller makes once and passes in:
  the module copies no rule. In this root it is the policy that admits WARP
  enrollment (`modules/zero-trust`), so the same people sign in to the tools.
- **Both logins** are offered, the one-time PIN and GitHub: `allowed_idps` is
  unset, so Cloudflare lists every provider of the account.

The client secret is returned on creation only, so it sits in the state. The
operator carries it into Vault from the root's `access_oidc_clients` output:
the procedure is in the repo's README, "Carrying the OIDC clients into Vault".

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.12 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 5.25.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.25.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_zero_trust_access_application.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/zero_trust_access_application) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the application, as the Access launcher shows it. | `string` | n/a | yes |
| <a name="input_policy_id"></a> [policy\_id](#input\_policy\_id) | ID of the reusable Access policy that decides who signs in: the one that admits the operator and the admins team. | `string` | n/a | yes |
| <a name="input_public_client"></a> [public\_client](#input\_public\_client) | Also a public client: the authorization code flow with PKCE, which a CLI runs with its client ID alone, besides the one with the client secret. | `bool` | `false` | no |
| <a name="input_redirect_uris"></a> [redirect\_uris](#input\_redirect\_uris) | Where the tool receives the login: its callback, and a CLI's local one. | `list(string)` | n/a | yes |
| <a name="input_team_name"></a> [team\_name](#input\_team\_name) | Zero Trust team name: the issuer lives at <team\_name>.cloudflareaccess.com. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | The OIDC client ID the tool signs in with. |
| <a name="output_client_secret"></a> [client\_secret](#output\_client\_secret) | The OIDC client secret. Cloudflare returns it on creation only, so it lives in the state from then on. |
| <a name="output_issuer"></a> [issuer](#output\_issuer) | The OIDC issuer URL: Cloudflare's documented form, with the discovery document under /.well-known/openid-configuration. |
<!-- END_TF_DOCS -->
