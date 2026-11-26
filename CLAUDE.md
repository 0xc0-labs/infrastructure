# infrastructure

The workspace's `CLAUDE.md` holds the org's rules, which apply here too; this
file holds only this repo's.

Proxmox VE 9 on two Hetzner dedicated servers, `pve-1` (`pve.0xc0.cc`) and
`pve-2`, one cluster, no ZFS. Both have 2× NVMe in mdadm RAID 1: `pve-1` was
reinstalled on 2026-11-25 by the README's "Adding a node" and rejoined over the
link with `pvecm add 10.20.0.2 --link0 10.20.0.1 --use_ssh`, since `pve-2`'s
`root` has no password. Each zone is a Linux
bridge over its Hetzner vSwitch on both nodes, not SDN. `pve-2` is router and
firewall and holds `.1` in every zone; `eno1` keeps the public IP, and egress
is SNAT through `eno1`. `pve-1`'s bridges are layer 2 only.

`pve-2`'s host also runs PBS, and `pve-1` has no Docker any more. PBS is
**not managed from this repo** and must never be touched by it: it
backs up to a Hetzner Storage Box. Traefik,
the reverse proxy for the Proxmox UI, PBS and RustFS, and RustFS, which holds
the OpenTofu state, run in `ct-base-01` and are managed here: OpenTofu makes
the container, Ansible configures what is inside it. Any change here that could
cut the host's public access — firewall rules on `eno1` above all — puts PBS
at risk.

OpenTofu (the official cloud image as a raw template, VMs, network, firewall)
→ Packer (the templates VMs clone: `debian-13-base`, `rocky-10-base`, and the
ones built on them)
→ Ansible (configuration). No VM clones the raw image.
Proxmox provider: `bpg/proxmox`. There is no SDN (0xc0-labs/infrastructure#289):
zones are Linux bridges over the vSwitches' VLAN interfaces, made by
`modules/zone-bridge` on every node, and the routing node's `.1` comes from
`zone_gateways`. Its SNAT, conntrack zone rule and MSS clamp are written by
hand in its `/etc/network/interfaces`.

Cloudflare — tunnels, Zero Trust, DNS, the applications' R2 buckets — lives
in the same root, `environments/prod/`, alongside the node (operator
decision, 2026-09-23): `prod` is the one environment, with everything that
makes it up. Split by service only if the coupling ever gets in the way.

## What runs

On the node: the zones, NAT, the zone and node firewalls, the Packer
templates, `vm-access-01` and `vm-access-02` (the admin connectors),
`vm-ci-01` and `vm-ci-02` with the self-hosted runners, and one RKE2 cluster
in `platform` behind the HAProxy load balancer pair that carries the public
tunnel. In the cluster: ArgoCD, Longhorn, the ingress (Traefik) with its WAF
(CrowdSec), and Vault, which holds every secret this repo uses
(`ci/infrastructure/*`, `ci/shared/*`). PBS backs every VM up daily. The
addressing plan of every VM is in `docs/zones.md`, Machines.

## Architecture

`docs/architecture.md` explains how the node, the zones, the flows, CI and the
secrets fit together, with diagrams. Read it before a change that touches more
than one of them. It explains; the code and the workspace's design
(`../docs/design/network.md`, `../docs/design/platform.md`) decide.

## Ansible

`ansible/` configures what runs inside the VMs, after cloud-init. **Every
playbook runs from the pipeline** (operator decision, 2026-09-29):
`.github/workflows/ansible.yml` calls the reusable workflow in
`0xc0-labs/.github`, which runs them at once, with `--check --diff` on a
PR, and for real on a merge to `main` once the operator approves. Nothing is
applied from the laptop.

Locally, only the dry run, through `scripts/ansible`, which reads the tunnel
token and the admin keys from the OpenTofu state into the environment, never
onto disk:

```
scripts/ansible playbooks/vm-access.yml --check --diff
```

Every play goes one host at a time (`serial`), so a bad change stops at the
first and the other keeps the service. A dry run changes nothing:
`scripts/ansible` runs it on every host at once (`play_serial`).

Ansible never touches the node. Every zone reaches the internet, so the node
needs no forwarding rule of its own. `pve-2` has no Docker: its forwarding
comes from `/etc/sysctl.d/90-ip-forward.conf` and its `FORWARD` policy is
ACCEPT by default (`docs/architecture.md`, The node). A zone that must never
egress would need a DROP rule in `FORWARD`; the `node_forwarding` role that
wrote one is in git history (#101). PBS is never touched from this repo.

Ansible reaches every VM directly over WARP.

`playbooks/vm-ci.yml` runs the `github_runner` role: ephemeral runners, each
fetching a just-in-time config from a GitHub App of their own before every
job. The App's key never reaches the CI VMs, `vm-ci-01` and `vm-ci-02`: it
lives in Vault's Transit, which signs the App's JWT for them. They hold only an
AppRole secret ID (`ci/infrastructure/runner-approle`), readable only by root,
whose token can do nothing but ask for that signature. Each of a VM's two
runners runs its jobs as an unprivileged user of its own, `runner-<n>`, and
builds images with a rootless BuildKit of its own, run as `buildkit-<n>`:
started empty before every job and stopped after it, so nothing a job builds
or caches outlives it or reaches the other runner (the role's `README.md`). No
secret goes on a command line there, where any process could read it. Each
runner carries the `0xc0` label and its VM's name, so a job can pin itself to
one VM.

`playbooks/cluster.yml` builds the cluster: `haproxy`, `keepalived` and the
public tunnel's `cloudflared` on the `lb` pair, holding the VIPs, then
`longhorn_node`, `rke2_server` and `argocd` on each server, one at a time, and
last `longhorn_node` and `rke2_agent` on each agent. The first server
initialises the cluster; the others join through the VIP, with the token from
Vault (`ci/infrastructure/rke2`). The `argocd` role writes ArgoCD's
`HelmChart` and the root `Application` into RKE2's manifests directory: RKE2's helm-controller
installs ArgoCD, and ArgoCD syncs `bootstrap/prod/` from `gitops` (operator
decision, 2026-09-29). There is no OpenTofu root for the cluster. The admin kubeconfig is
stored nowhere but on the servers (operator decision, 2026-09-29): whatever
needs it, the pipeline or the laptop, reads it over SSH from a server, into
memory.

Every role follows the `ansible-role` skill and passes `ansible-lint` on the
`production` profile.

Ansible and ansible-lint do not come from mise. `pyproject.toml` pins them,
and `uv.lock` pins them and every Python package under them, with hashes, and
their Python. The wrappers the pipeline calls (`scripts/ansible`,
`scripts/packer`) install exactly that lock, wheels only, and put it first on
`PATH` (`scripts/python-env`): nothing is resolved on the runners. A
dependency changes only through a PR that updates the lock (`uv lock`).
Locally, from `ansible/`: `uv run --frozen --group lint ansible-lint`.

## Packer

`packer/<template>/` bakes the templates every VM clones, in
`packer/build-order`: `debian-13-base` from the raw `debian-13-cloud`, with the
`base` role, `debian-13-runner` from `debian-13-base`, with the runner, and
`rocky-10-base` from the raw `rocky-10-cloud`, with the `base` role, for the
RKE2 nodes.
Secrets and per-VM settings stay in Ansible. `scripts/packer <template>
validate` locally. A merge to `main` that touches a template or its roles
rebuilds it, and every template cloning it, in CI, after approval: each one
built beside the old one, as `<name>-next`, and swapped in for it only once it
succeeds, so a build that fails or is cut leaves the old template in place
(`scripts/proxmox-template`, #207). Skill `packer-template`.

## Network source of truth

The code: `environments/prod/terraform.tfvars` holds the zones, the VMs, the
transit matrix (`transit`) and the node's admin ports (`node_firewall`). The
`zone-firewall` module turns the matrix into every zone's and the node's rules;
nothing is generated into a file. Validations in `variables.tf` enforce the
invariants they can.

`docs/zones.md` explains that data and keeps what cannot be code: the five
reserved ranges that can never be used (a second node, Hetzner Cloud, RKE2
pods and services, lab), the addressing plan, the Packer build addresses and
the invariants.

## Hard rules

- Every firewall rule comes from the `transit` matrix in `terraform.tfvars`
  (skill `firewall-matrix`), never written as a resource by hand. Its comment
  is `<from> -> <to>: <note>`, so any rule in Proxmox traces back to its line.
- Zone filtering happens on each guest's NIC (`modules/zone-firewall`). Every
  VM has its own firewall on: the node's `FORWARD` policy is ACCEPT, so a VM
  without one is not filtered at all.
- No zone must initiate towards a destination that isn't in `transit`: an
  entry with an empty `to` gives that zone's VMs an outbound DROP policy. None
  today, but the mechanism stays for a zone that must never egress.
- No other zone initiates towards `mgmt`, with two exceptions: SSH from the
  CI VMs named in its `transit` entry (`sources`), never the whole `ci` zone,
  so the pipeline can run the vm-access playbook (operator decision,
  2026-09-29); and TCP 20241 from `platform`, towards `vm-access-01` and
  `vm-access-02` alone (`targets`), for Prometheus to read the admin tunnel's
  connector metrics (operator decision, 2026-11-26). Besides those, SSH
  between the `vm-access` connectors, inside `mgmt`, is the only way in.
- The node has a DROP policy (`node_firewall_enabled`): 22 and 8006
  from `mgmt`, 8006 from `ci`, 9100 from `platform`, and
  only SSH (22) from the internet, as break-glass, bound to the node's public
  NIC (`eno1`) so no zone reaches it: the Hetzner firewall keeps it closed
  until the operator opens it, and sshd is key-only. No zone gets
  443: the web names go to `ct-base-01`. All of it from the matrix.
  Day-to-day admin access is over WARP: the node's own over 22 and 8006 at
  `10.10.0.1`, and the web names (Proxmox UI, PBS, RustFS) at `ct-base-01`,
  where Gateway resolves `base_service_hostnames`. The Hetzner Rescue system
  is the last way back in.
- `local_network` is overridden to loopback, so Proxmox grants no implicit
  admin access to the network it detects. Never remove that alias.
- A change to the node firewall is tested first by hand, with a rollback
  scheduled on the node itself (systemd timer), before it goes into code.
- `ci` reaches the node over 8006 (API), never over 22, and neither does
  `platform`: from the internet, 22 is admitted on the public NIC alone.
- No admin interface reaches the internet through the public tunnel: the
  portals, Vault and the Kubernetes API are reached only over WARP, through
  the admin tunnel. No portal is published behind Cloudflare Access either.
- Idempotent playbooks: no `shell`/`command` without `creates:` or
  `changed_when:`.
- Disks and volumes holding data carry `lifecycle { prevent_destroy = true }`.
- The provider **never** gets SSH to the node. Everything goes through the API:
  import disks with `import_from`, never `file_id`; no cloud-init snippets.
  Both would make the provider SSH into the host. Packer bakes the shared
  baseline into the template; Ansible configures each VM from there.
- Nobody picks a VM's VMID: Proxmox assigns the next free one, from 100, and
  the state keeps it. Every NIC has the Proxmox firewall on, or zone rules do
  not apply to it.
- **No VM is destroyed** as a matter of course: the `vm` module sets
  `prevent_destroy`, so a plan that deletes or replaces one fails. A deliberate
  rebuild bumps the VM's `rebuild` in `terraform.tfvars` **and** lifts
  `prevent_destroy` in the same PR; the next PR sets it back. No run ever
  restarts a VM on its own either (`reboot_after_update = false`): a change
  that needs one stays pending in Proxmox, and `scripts/rolling-reboot
  <vm>...` restarts them one at a time, waiting for each (and, for an RKE2
  node, its node Ready and Longhorn healthy) before the next. A CI VM is
  rebuilt from the pipeline too, one at a time: the same PR points
  `.github/workflows/apply.yml`'s `runs-on` at the **other** VM's label, so
  the apply never runs on the VM it destroys; the next PR points it back at
  `0xc0`.
- Templates are found by **name**, never by VMID. Each still takes a fixed
  VMID, so the ID says what it is: 9000-9099 for the raw images (`vm_id` in
  `templates`), 9100-9149 for Packer's (`vm_id` in the template's
  variables), kept across rebuilds, and that ID plus 50 for a template's next
  build until it is swapped in. The raw cloud image is a pinned, dated
  build with its published checksum, never a `latest` link. A VM ignores later
  changes to its template; moving it onto a new one is bumping its `rebuild`.
- Keep a root under a few dozen resources: every run refreshes all of it.

## Before opening a PR

If the change touches network, firewall, addressing or inventory, the
session making it checks it against every invariant in `docs/zones.md`,
Invariants, before opening the PR.

## Skills in this repo

Under `.claude/skills/`, for the operations that repeat here:

| Skill             | Use it when                                          |
|-------------------|------------------------------------------------------|
| `new-vm`          | adding, moving or re-addressing a VM                 |
| `firewall-matrix` | opening, closing or reviewing a port between zones   |
| `packer-template` | a baked template                                     |
| `ansible-role`    | creating, restructuring or reviewing a role          |

`new-vm` and `firewall-matrix` both edit `environments/prod/terraform.tfvars`,
which decides, and keep `docs/zones.md`, which explains, in step.

## Claude Code plugins enabled here

`0xc0@0xc0-labs` (hooks and skills) and `terraform@hashicorp` (official
HashiCorp skills), both declared in `.claude/settings.json`.

Caveats:

- They are written for Terraform; this repo runs **OpenTofu**. Treat their
  output as a starting point and check the command names and any
  Terraform-Cloud-only feature.
- The `terraform-stacks` skill may trigger on its own. Stacks is **discarded**
  here (paid). Ignore it if it fires.
- The `packer@hashicorp` plugin is deliberately **not** enabled: its four
  skills are AWS, Azure, Windows and HCP registry. None applies to Proxmox.
