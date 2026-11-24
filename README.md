# infrastructure

OpenTofu, Packer and Ansible for the 0xc0-labs node: its zones, its
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
earlier one, and the rescue system assembles those arrays by itself. On
`pve-2`, the install that was not meant to run had put the members of the
system's arrays (`md0`, `md1`, `md2`) on all four drives, so the two left out
still carried them and the arrays came back after the first reboot.

Clearing is only for a drive that carries leftover members of an earlier
**system** install and nothing to keep. A drive that holds data is left
alone: nothing in this runbook touches it. Tell them apart before running
anything, in the rescue system:

```
cat /proc/mdstat
lsblk -o NAME,SIZE,TYPE,FSTYPE
```

A leftover is a partition that is a member of the same arrays as the system
drives' partitions. Only for those, and only for the arrays they belong to
(not every array on the server):

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
  answer on the host only. It is removed before the cluster is formed, which
  needs the API between the nodes: [Forming the cluster](#forming-the-cluster),
  step 3.
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

Creating or joining a cluster ([Forming the cluster](#forming-the-cluster)),
any guest (a node joins empty), Docker, PBS,
Traefik. The vSwitches the node is attached to are in
[`docs/zones.md`](docs/zones.md#vswitches).

## Forming the cluster

How `pve-1` and `pve-2` become one Proxmox cluster, named `cluster`: two nodes,
no QDevice, no HA. `pve-1` holds 2 votes and `pve-2` 1, so `pve-1` keeps quorum
alone. One corosync link, on the vSwitch `cluster`
([`docs/zones.md`](docs/zones.md#vswitches)): a second one, on the public
addresses, would ride the same NIC and need the last free rule of each server's
firewall in Robot. The operator runs every step, in order; nothing is applied
from a pipeline but step 2.

Before it: both nodes at the same `pve-manager` (`pveversion`) and corosync
(`corosync -v`): bring the one behind level first. A kernel waiting for a
reboot does not stop a join.

1. **Forwarding, on a node that routes for the zones** (`pve-1`, which
   holds the zones' gateway and SNAT; a node whose guests reach them over the
   vSwitch needs none). Why:
   [`docs/architecture.md`](docs/architecture.md#the-node).

   ```
   echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/90-ip-forward.conf
   sysctl --system
   ```

   Seen: `sysctl net.ipv4.ip_forward` gives `1`, and still would without
   Docker.

2. **Approve the apply** of the PR that holds `node_link` and `node_links`. It
   makes `eno1.4000` on each node of `nodes`, and the datacenter's `management`
   set. Seen, on `pve-1`: `ip -br addr show eno1.4000` gives `10.20.0.1/24`,
   the interface is in `/etc/network/interfaces`, and `pve-firewall status` is
   `enabled/running`. From `pve-2`: `nc -vz 10.20.0.1 22` answers.

3. **On `pve-2`, leave it empty**: no guest, so remove what a rehearsal left
   (`qm list`, the SDN zones in `/etc/pve/sdn`, test users, roles and tokens in
   `pveum`, any `/etc/sysctl.d/90-*-forward.conf`), and the `LISTEN_IP` line of
   `/etc/default/pveproxy`, then:

   ```
   systemctl restart pveproxy
   ```

   Seen: `qm list` is empty, and `ss -tlnp` no longer shows 8006 on loopback
   alone.

4. **On each node, its name on its link address**, the address the other node
   uses for the API, SSH and migration, and the one Hetzner's firewall and the
   set admit. In `/etc/hosts`, the lines of the node's name become
   `10.20.0.1 pve-1` (`pve-2`: `10.20.0.2 pve-2`). Then:

   ```
   systemctl restart pve-cluster pvedaemon pveproxy pvestatd
   pvecm updatecerts --force
   ```

   Seen: `hostname --ip-address` gives the link address. Do it on `pve-1`
   first.

5. **On `pve-1`, create the cluster:**

   ```
   pvecm create cluster --link0 10.20.0.1 --votes 2
   ```

6. **On `pve-2`, join it.** It asks for `pve-1`'s `root` password, which only
   the operator types.

   ```
   pvecm add 10.20.0.1 --link0 10.20.0.2
   ```

7. **See it:** `pvecm status` on both nodes gives `Expected votes: 3`,
   `Total votes: 3` and `Quorate: Yes`, and `ssh 10.20.0.2 hostname` from
   `pve-1` prints `pve-2`. **From this moment `pve-2`'s SSH on its public
   address is closed**, until its node rules apply (step 8): it is reached
   over the link.

8. **Approve the apply** of the PR that puts `pve-2` in `nodes` (#277). It
   gives the joined node its firewall options and the same rules as `pve-1`.
   On `pve-2`, reached from `pve-1` (`ssh 10.20.0.2`), check that its firewall
   runs, and start it if it does not:

   ```
   systemctl start pve-firewall
   pve-firewall status
   ```

   Seen: `enabled/running`, `/etc/pve/nodes/pve-2/host.fw` holds the node's
   rules, and `pve-2`'s SSH answers again on its public address.

9. **Point the PBS storage at the link**, once the apply of the PR that admits
   8007 from the nodes' link has run (before it, another node does not reach
   PBS). `server` is a fixed parameter of a PBS storage, so `pvesm set`
   refuses to change it. Edit the `server` line of `pbs: sbox` in
   `/etc/pve/storage.cfg`, the cluster's file, then drop the node restriction:

   ```
   sed -i -E 's/^([[:space:]]+server) 127\.0\.0\.1$/\1 10.20.0.1/' /etc/pve/storage.cfg
   pvesm set sbox --delete nodes
   pvesm status
   ```

   Seen: `pvesm status` shows `sbox` active on both nodes. The daily job,
   which names no node, then backs up each node's guests to it.

10. **The zones' bridges** come with the node's entry in `nodes`: the root
    makes, on every node of `nodes`, the VLAN interface of each zone and the
    bridge named as the zone over it (`modules/zone-bridge`), at MTU 1400. A
    new node gets them by entering `nodes`, layer 2 only, with no address.
    It routes for a zone only with an entry in `zone_gateways`, given with
    its first guest.

## Changing a guest's NIC

A NIC setting, such as the `mtu` every VM and template carries, is read when
the VM's process starts: it takes effect at a stop and start from Proxmox,
not at a reboot from inside the guest. Changing it on a running VM makes
Proxmox unplug the NIC and plug it again, and an apply would do that to every
VM at once, so a change that needs it is made by hand, one guest at a time,
before the PR that declares it: shut the guest down, edit its `net0`, start it,
check it from inside. **Never on a running RKE2 node**: the pod network's tunnel
sits on that NIC and goes with it. Take them one at a time, with the node Ready
(`flannel.1` at the new size), Vault's pod unsealed on it and Longhorn's volumes
healthy before the next. The PR's plan then shows nothing to change.

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
