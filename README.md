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

## Adding a node

How a Proxmox node is installed for this org, written from `pve-2`
(2026-11-23, 0xc0-labs/infrastructure#273), which was installed to match
`pve-1`. The same steps reinstall a node. The operator runs them on the
server; nothing here is applied from a pipeline. The node joins nothing and
runs no guest until the cluster exists (the last step).

What differs between nodes: the **hostname**, final once the node is in a
cluster, since a node's name does not change; the **RAID level**; the
**drives** named. Everything else is the same on every node, the partitioning
included: `local`, a `dir` storage at `/var/lib/vz`, is then the same storage
everywhere, and `storage.cfg` is the cluster's.

### 1. Rescue system and `installimage`

In Hetzner Robot, activate the rescue system for the server **with an SSH
key**, not a password, and reset the server. Sign in as `root`.

> **Do not order an automatic install in Robot.** It runs at the next
> reboot, with every default, over whatever the rescue system was meant to
> leave alone. On `pve-2` it did.

A drive left out of the install keeps the partitions and RAID members of an
earlier one, and the rescue system assembles those arrays by itself. Clear
every drive that is not named below before installing, or its old arrays come
back after the first reboot:

```
mdadm --stop /dev/md0 /dev/md1 /dev/md2
mdadm --zero-superblock <each leftover partition>
wipefs -a <each leftover partition>; sgdisk --zap-all <the drive>; wipefs -a <the drive>
```

Then, in `installimage`'s batch mode, which asks nothing and **erases the
drives it names**. This is `pve-2`: change `-n` for the hostname, `-l` for the
RAID level (`pve-1` is `-l 0`, an accepted risk, `docs/architecture.md`,
Disks; `pve-2` is `-l 1`) and `-d` for the drives:

```
installimage -a -n pve-2 -r yes -l 1 \
  -i /root/.oldroot/nfs/images/Debian-1305-trixie-amd64-base.tar.zst \
  -p "swap:swap:32G,/boot:ext3:1024M,/:ext4:all" -d nvme0n1,nvme1n1 -f no -t yes
```

`-t yes` carries the rescue system's SSH key into the installed system.
`installimage` gives the hostname the public address in `/etc/hosts`, which
Proxmox requires to be no loopback address, so that file needs nothing. Reboot
into Debian 13 (trixie).

### 2. Proxmox VE on Debian

Following Proxmox's "Install Proxmox VE on Debian 13 Trixie". The repository
file is named as on `pve-1`; the checksum is the one Proxmox's guide lists:

```
cat > /etc/apt/sources.list.d/proxmox.sources <<'EOL'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOL
wget -q https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg -O /usr/share/keyrings/proxmox-archive-keyring.gpg
echo "136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45  /usr/share/keyrings/proxmox-archive-keyring.gpg" | sha256sum -c -
apt-get update && apt-get -y full-upgrade
apt-get -y install proxmox-default-kernel ethtool
systemctl reboot
```

After the reboot into the Proxmox kernel. `pveproxy` is set to listen on the
host only **before** `proxmox-ve` is installed, so it never answers on the
public address:

```
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string $(hostname)" | debconf-set-selections
printf 'LISTEN_IP="127.0.0.1"\n' > /etc/default/pveproxy
DEBIAN_FRONTEND=noninteractive apt-get -y install proxmox-ve postfix open-iscsi chrony
apt-get -y remove linux-image-amd64 'linux-image-6.12*'
update-grub
apt-get -y remove os-prober
systemctl disable --now rpcbind.socket rpcbind.service
rm /etc/apt/sources.list.d/pve-enterprise.sources
```

The bridge `vmbr0` that Proxmox's guide creates is **not** made: the zones'
bridges come from OpenTofu.

### 3. Closed until the node's firewall exists

A freshly installed node answers on its public address, and its firewall
arrives with the cluster. Until then:

- `sshd` by key only: `PasswordAuthentication no` in
  `/etc/ssh/sshd_config.d/10-key-only.conf`. `installimage` already leaves
  `root` with no password, so nobody signs in to the web interface with one.
- `LISTEN_IP="127.0.0.1"` in `/etc/default/pveproxy` (step 2): 8006 and 3128
  answer on the host only. It is removed when the cluster is formed, which
  needs the API between the nodes.
- `rpcbind` disabled (step 2): nothing uses NFS, and an open port 111 on a
  public address draws abuse reports.

After it, check with `ss -tlnp` that only 22 listens on the public address.

### 4. Set by hand

- **`eno1`'s offloads**, when its driver is `e1000e` (`ethtool -i eno1`): the
  `post-up` line in the `iface eno1 inet static` stanza, and
  `ethtool -K eno1 tso off gso off` once, so it holds before the first reboot.
  Why and the line itself: [`docs/architecture.md`](docs/architecture.md#the-node).
- **Hetzner's firewall**, in Robot: the same incoming rules as the other
  nodes, ending in `deny all`, and the two rules for the private ranges. Why
  they are needed: [`docs/architecture.md`](docs/architecture.md#the-node).

[`docs/architecture.md`](docs/architecture.md#the-node) describes `pve-1`,
which also runs Docker, PBS, Traefik and RustFS. Those paragraphs do not apply
to a node without them.

### 5. Not before the join

Creating or joining a cluster, any guest (a node joins empty), Docker, PBS,
Traefik. The vSwitches the node is attached to are in
[`docs/zones.md`](docs/zones.md#vswitches).

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
