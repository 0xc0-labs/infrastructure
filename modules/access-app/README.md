# access-app

One hostname behind Cloudflare Access, open to a group of viewers the
operator manages in the dashboard.

- **A group**, `<name> viewers`: who may see the hostname. It is seeded with
  `operator_emails` because Cloudflare refuses a group with no members.
  **OpenTofu ignores its members** (`ignore_changes = [include]`): what the
  operator adds or removes in the dashboard stays, and no apply is needed.
- **A policy**, `allow`, that includes the group, `operator_emails` and the
  GitHub team `github_organization/github_team`, so the operator gets in even
  if the group is emptied. The team is in the policy, not the group: OpenTofu
  ignores the group's members.
- **A self-hosted application** on `domain`, with two logins: the account's
  one-time PIN (`identity_provider_id`: a code sent by email) and GitHub
  (`github_identity_provider_id`). The session lasts `session_duration` (24
  hours by default). The visitor picks one on Cloudflare's login page.

- **Bypass applications**, one per path in `bypass_paths` (none by default): a
  self-hosted application on `domain` plus the path, with one policy,
  `bypass`, that includes everyone. Cloudflare applies the most specific path
  first, so that path and what is under it skip the login, and the
  hostname's own application and policy are unchanged. It is for a caller
  that cannot log in, a webhook. **Anyone can reach a bypassed path**, so it
  must authenticate its callers itself.

OpenTofu owns everything but the group's members. The identity providers are
`zero-trust`'s.

## Adding or removing a viewer

In Cloudflare: Zero Trust → Access → Access groups → `<name> viewers` → edit
its emails. Nothing is applied.

The hostname needs no record of its own here: it gets its public record when
the route that serves it is published (gitops).

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
| [cloudflare_zero_trust_access_application.bypass](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/zero_trust_access_application) | resource |
| [cloudflare_zero_trust_access_application.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/zero_trust_access_application) | resource |
| [cloudflare_zero_trust_access_group.viewers](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/zero_trust_access_group) | resource |
| [cloudflare_zero_trust_access_policy.bypass](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/zero_trust_access_policy) | resource |
| [cloudflare_zero_trust_access_policy.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/zero_trust_access_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID. | `string` | n/a | yes |
| <a name="input_bypass_paths"></a> [bypass\_paths](#input\_bypass\_paths) | Paths on the hostname, and what is under them, reached without a login. Anyone can reach them: each must authenticate its callers itself. | `list(string)` | `[]` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | Hostname the application protects. | `string` | n/a | yes |
| <a name="input_github_identity_provider_id"></a> [github\_identity\_provider\_id](#input\_github\_identity\_provider\_id) | ID of the account's GitHub identity provider, the other login offered. | `string` | n/a | yes |
| <a name="input_github_organization"></a> [github\_organization](#input\_github\_organization) | GitHub organization of the team the policy lets in. | `string` | n/a | yes |
| <a name="input_github_team"></a> [github\_team](#input\_github\_team) | Team of github\_organization let in beside the operator and the group. | `string` | n/a | yes |
| <a name="input_identity_provider_id"></a> [identity\_provider\_id](#input\_identity\_provider\_id) | ID of the account's one-time PIN identity provider, a login offered. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the application. The group and the policy are named after it. | `string` | n/a | yes |
| <a name="input_operator_emails"></a> [operator\_emails](#input\_operator\_emails) | The operator's emails: the group's seed, and let in by the policy whatever the group holds. | `list(string)` | n/a | yes |
| <a name="input_session_duration"></a> [session\_duration](#input\_session\_duration) | How long a login lasts. | `string` | `"24h"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_application_id"></a> [application\_id](#output\_application\_id) | ID of the Access application. |
| <a name="output_group_id"></a> [group\_id](#output\_group\_id) | ID of the viewers' group. |
<!-- END_TF_DOCS -->
