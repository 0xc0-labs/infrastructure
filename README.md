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

## gVisor on vm-rke2-04

`vm-rke2-04` runs gVisor, as a test (2026-11-20, 0xc0-labs/workspace#266): the
`rke2_agent` role installs `runsc` there and registers it in RKE2's containerd
as the runtime `runsc`. `runsc` refuses a container that carries an SELinux
label, and containerd has no switch per runtime, so the node's containers are
given none (`selinux: false` in its RKE2 config). The host stays Enforcing and
`rke2-selinux` stays installed; what changes is that **every pod on that node
runs unlabelled**, the shared PostgreSQL, MariaDB, Vault's replica and
OpenObserve among them. The RuntimeClass and the pods that use `runsc` are in
`gitops`.

The way back, in `ansible/inventory/hosts.yml`, on `vm-rke2-04`: delete
`rke2_agent_container_selinux: false` and `rke2_agent_gvisor: true` (their
defaults are `true` and `false`), merge, and let the pipeline run the cluster
playbook. The role removes the template, the binaries and the file-context
rules, and restarts `rke2-agent` once; the node's pods are labelled again as
they restart.

## Private buckets

`artistlabco-com-resources` and `artistlabco-com-staging-resources` are
artistlabco.com's Strapi's gated resources: private, with no custom domain, no
`r2.dev` URL and no CORS, since downloads go by signed URL. Its token is not written
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
itself; this one is Stripe's signature, checked by the front, in
`0xc0-labs/artistlabco.com`'s `src/app/api/stripe/webhook/route.ts`
(artistlabco.com#40).

To add or remove a viewer, in Cloudflare: Zero Trust → Access → Access groups
→ the group → edit its emails. No apply is needed: OpenTofu ignores the group's
members and owns everything else (`modules/access-app/README.md`).

The Traefik, RustFS and PBS running on the node are **not** managed here.
