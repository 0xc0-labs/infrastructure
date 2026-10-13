# access-app

One hostname behind Cloudflare Access, open to a group of viewers the
operator manages in the dashboard.

- **A group**, `<name> viewers`: who may see the hostname. It is seeded with
  `operator_emails` because Cloudflare refuses a group with no members.
  **OpenTofu ignores its members** (`ignore_changes = [include]`): what the
  operator adds or removes in the dashboard stays, and no apply is needed.
- **A policy**, `allow`, that includes the group and `operator_emails`, so
  the operator gets in even if the group is emptied.
- **A self-hosted application** on `domain`, whose only login is the
  account's one-time PIN, `identity_provider_id`: the visitor gets a code by
  email and the session lasts `session_duration` (24 hours by default). The
  login redirects straight to the PIN page.

OpenTofu owns everything but the group's members. The identity provider is
`zero-trust`'s.

## Adding or removing a viewer

In Cloudflare: Zero Trust → Access → Access groups → `<name> viewers` → edit
its emails. Nothing is applied.

The hostname needs no record of its own here: it gets its public record when
the route that serves it is published (gitops).

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
