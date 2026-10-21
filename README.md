# infrastructure

OpenTofu, Packer and Ansible for the 0xc0-labs node: its SDN zones, its
firewall, the VMs on it, and the RKE2 cluster they run.

- **How it fits together:** [`docs/architecture.md`](docs/architecture.md)
- **The network:** decided in [`environments/prod/terraform.tfvars`](environments/prod/terraform.tfvars), explained in [`docs/zones.md`](docs/zones.md)
- **Why it is this way:** the workspace's design, [`network`](https://github.com/0xc0-labs/workspace/blob/main/docs/design/network.md) and [`platform`](https://github.com/0xc0-labs/workspace/blob/main/docs/design/platform.md); what was discarded, [`discarded.md`](https://github.com/0xc0-labs/workspace/blob/main/docs/discarded.md)

```
environments/prod/      the root for the node — only calls modules
modules/<name>/         the resources
packer/<template>/      bakes the templates every VM clones
scripts/tofu             runs tofu on an environment, secrets from Vault in env
scripts/ansible          runs ansible-playbook, tunnel tokens and secrets in env
scripts/vault-env        sourced by the others: each secret from Vault, unless set
scripts/packer           validates or builds a template; a build replaces it once it succeeds
scripts/proxmox-template sourced by scripts/packer: swaps a template's next build in
scripts/rolling-reboot   restarts VMs one at a time, waiting for each
ansible/                 what runs inside the VMs: inventory, playbooks, roles
.github/workflows/       plan, apply, ansible, packer and issue-check pipelines
docs/                    architecture and the zone matrix
```

## Running it

Tools come from `mise.toml`. Secrets come from Vault, over WARP, and never
touch disk:

```
vault login -no-print
scripts/tofu prod init
scripts/tofu prod plan
```

Every change goes through a PR linked to an issue. `plan` comments the plan on
the PR; `apply` runs after merge and waits for the operator's approval. The
conventions are the org's, in
[`0xc0-labs/.github`](https://github.com/0xc0-labs/.github#conventions).

## Private buckets

`payload-resources` and `payload-staging-resources` keep Payload's gated
resources: no custom domain, no `r2.dev` URL, no CORS, since downloads go by
signed URL from Payload. After the apply, the operator creates an R2 API token
per bucket (object read and write, limited to that bucket) and writes it to
Vault at `apps/payload/resources-storage` and
`apps/payload-staging/resources-storage`, with the keys `bucket`, `endpoint`,
`access_key_id` and `secret_access_key` (generic block: `vault`'s README).

`artistlabco-com-resources` and `artistlabco-com-staging-resources` are
artistlabco.com's Strapi's, private the same way. Its token is not written
to Vault by the operator: it is entered in Strapi's Integraciones
(Almacenamiento), which writes it.

## Hostnames behind Access

`access_apps` puts a hostname behind Cloudflare Access, today
`staging.artistlabco.com` and the admin of artistlabco.com's Strapi,
`cms.artistlabco.com` and `cms-staging.artistlabco.com`, with no bypass. Each gets a group of viewers, `<name> viewers`, and
logs in by a one-time PIN sent to the visitor's email, for 24 hours. The
operator, `warp_allowed_emails` from Vault, always gets in.

`bypass_paths` lets a path, and what is under it, skip the login, for a caller
that cannot log in: `staging.artistlabco.com/api/stripe/webhook`, Stripe's
webhook. Anyone can reach a bypassed path, so it must authenticate its callers
itself; this one is Stripe's signature, checked by Payload (artistlabco.com#40,
payload#77).

To add or remove a viewer, in Cloudflare: Zero Trust → Access → Access groups
→ the group → edit its emails. No apply is needed: OpenTofu ignores the group's
members and owns everything else (`modules/access-app/README.md`).

The Traefik, RustFS and PBS running on the node are **not** managed here.
