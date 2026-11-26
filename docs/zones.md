# Zones

How the network is laid out, and why. **The code decides**: the zones,
the VMs, the transit matrix and the node's ports live in
[`environments/prod/terraform.tfvars`](../environments/prod/terraform.tfvars),
and the `zone-firewall` module turns the matrix into rules. This document
explains that data and keeps what cannot be code: the reserved ranges, the
addressing plan, and the invariants.

## Zones

Each zone is a plain Linux bridge over its Hetzner vSwitch on every node
(`modules/zone-bridge`): the VLAN interface `eno1.<vlan>` is the bridge's only
port, both at MTU 1400, and every guest's NIC names the bridge. The gateway is
`.1`, held by one node alone (`zone_gateways`): `pve-2`, while `pve-1` is away.
It also does the SNAT for egress through `eno1`, to its public address
`142.132.139.52`. A node with no entry in `zone_gateways`, `pve-1` today, has
the bridge at layer 2 only, and its guests' gateway is `pve-2`'s `.1` across
the vSwitch. `pve-1`, reinstalled with RAID 1 and rejoined on 2026-11-25,
takes the role back in the next steps of workspace#285. The zones are the `zones` map in `terraform.tfvars`, keyed
by bridge name (at most 8 letters and digits); `alias` is the name everything
else uses.

| Zone | CIDR | Bridge | VLAN |
|---|---|---|---|
| `mgmt` | 10.10.0.0/24 | `mgmt` | 4001 |
| `ci` | 10.10.1.0/24 | `ci` | 4002 |
| `platform` | 10.10.4.0/24 | `platform` | 4003 |

The routing node's SNAT and conntrack zone rule are lines in its bridge stanza
of `/etc/network/interfaces`, written by hand on `pve-2`: the provider's bridge
resource has no free line, and the API keeps hand-written lines when it
rewrites a stanza. The MSS clamp is in its `eno1` stanza
([`architecture.md`](architecture.md#the-node)). For `platform`:

```
auto platform
iface platform inet static
	address 10.10.4.1/24
	bridge-ports eno1.4003
	bridge-stp off
	bridge-fd 0
	mtu 1400
	post-up iptables -t nat -C POSTROUTING -s 10.10.4.0/24 -o eno1 -j SNAT --to-source 142.132.139.52 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.10.4.0/24 -o eno1 -j SNAT --to-source 142.132.139.52
	post-down iptables -t nat -D POSTROUTING -s 10.10.4.0/24 -o eno1 -j SNAT --to-source 142.132.139.52
	post-up iptables -t raw -C PREROUTING -i fwbr+ -j CT --zone 1 2>/dev/null || iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone 1
```

The `-C` test makes each `post-up` add its rule once however many times the
network reloads. `pve-1`'s bridges are `inet manual`: no address and no SNAT,
layer 2 only. The conntrack zone rule stays on `pve-1`, for its guests'
firewall bridges.

`mgmt` and `ci` together, `10.10.0.0/22`, are the control zones: the only ones
that reach the node's admin ports. `platform` holds the RKE2 cluster and the
LB pair: the public tunnel, the API, the data services and the web ingress all
live inside it, so it is the only zone with a broad set of internal rules
(below).

## Reserved ranges

No zone, VM or service may use these ranges. **Always** check before proposing
a new IP. The `zones` validation keeps every zone inside `10.10.0.0/16`, which
none of them touches.

| Range | For |
|---|---|
| 10.11.0.0/16 | a second node (none exists) |
| 10.20.0.0/16 | Hetzner Cloud and vSwitch; `10.20.0.0/24` is taken by the nodes' link ([vSwitches](#vswitches)), the rest is free |
| 10.42.0.0/16 | RKE2 pods |
| 10.43.0.0/16 | RKE2 services |
| 10.66.66.0/24 | lab (none exists) |

## vSwitches

Hetzner vSwitches, in Robot since 2026-11-23, with both nodes attached
(`pve-1` and `pve-2`; [Adding a node](../README.md#adding-a-node)). Hetzner
admits VLANs 4000 to 4091, 5 vSwitches a server and an MTU of 1400 at most.

| vSwitch | VLAN | Carries |
|---|---|---|
| `cluster` | 4000 | the nodes' link, `10.20.0.0/24`: `pve-1` `.1`, `pve-2` `.2` |
| `mgmt` | 4001 | the `mgmt` zone, `10.10.0.0/24` |
| `ci` | 4002 | the `ci` zone, `10.10.1.0/24` |
| `platform` | 4003 | the `platform` zone, `10.10.4.0/24` |

They are created and attached. On `cluster` each node holds its address
(`node_links` in `environments/prod/terraform.tfvars`, the interface `eno1.4000`
with MTU 1400): `pve-1` holds `10.20.0.1` and `pve-2` `10.20.0.2`.
`modules/node-link` makes the interface for every node of `nodes`; `pve-2`'s was
made through the API during the rehearsal and was imported into the state when
it entered `nodes` (#277). The other three carry the zones, as bridges
(Zones, above), on both nodes. Hetzner's firewall filters the vSwitches too
([`architecture.md`](architecture.md#the-node)).

**Every guest is at MTU 1400**, because a vSwitch carries no more. It is set on
the guest's NIC (`mtu` of `modules/vm` and `modules/cloud-image-template`, from
`node_link.mtu`), and the guest takes it as its maximum when its VM starts,
with nothing set inside it. On 2026-11-24, `pve-1`'s bridges were given their
vSwitch port at 1400 while the guests were still at 1500, and it had to be
undone (#284). Two things broke, and each needs its own fix:

- A guest left at 1500 behind a route at 1400 sends packets the route drops,
  and the node's MSS clamp covers TCP handshakes only
  ([`architecture.md`](architecture.md#the-node)). Putting every guest at 1400
  fixed it.
- A guest's NIC at 1400 limits what the guest sends, not what it is sent. The
  Cloudflare tunnels are QUIC over UDP, which the clamp does not reach:
  Cloudflare's edge had sized its packets for a 1500 path and kept sending them
  after the route narrowed. The tunnels stayed up on small packets and carried
  nothing large, such as an SSH key exchange. `pve-1` counted the drops:
  `nstat IpFragFails` rose about seven a second. Restarting `cloudflared` on
  the four VMs that run it ended it at once, since a tunnel opened on the
  narrower path sizes itself for it (README, Changing a guest's NIC).

## Machines

What exists is the `vms` map in `terraform.tfvars`, `cluster` for the RKE2
nodes and their load balancers, and `containers` for the LXC containers. Each
machine names the Proxmox node it runs on, its `node`, which must be one of
`nodes` **(code)**; every one says `pve-2` while `pve-1` is away, and `pve-1` takes its share back
once it has rejoined (workspace#285).
A guest moves between nodes live, with its disks, over the link, and the
`node` is changed only after the move ([`architecture.md`](architecture.md#the-node)).
The addressing plan, so that no address is handed out twice:

| Machine | Zone | IP |
|---|---|---|
| `vm-access-01` | mgmt | 10.10.0.10 |
| `vm-access-02` | mgmt | 10.10.0.20 |
| `vm-ci-01` | ci | 10.10.1.10 |
| `vm-ci-02` | ci | 10.10.1.20 |
| `ct-base-01` | ci | 10.10.1.30 |
| `vm-lb-01` | platform | 10.10.4.11 |
| `vm-lb-02` | platform | 10.10.4.12 |
| `vm-rke2-01` | platform | 10.10.4.21 |
| `vm-rke2-02` | platform | 10.10.4.22 |
| `vm-rke2-03` | platform | 10.10.4.23 |
| `vm-rke2-04` | platform | 10.10.4.24 |
| `vm-rke2-05` | platform | 10.10.4.25 |
| `vm-rke2-06` | platform | 10.10.4.26 |

`ct-base-01` is an unprivileged LXC container, Debian 13, 1 core, 1 GiB and 8 GB
(`modules/container`), the home of the base services: Traefik and RustFS. It is in `ci` because the runners reach RustFS, which
holds the OpenTofu state, and nothing enters `mgmt` from another zone but SSH
from the CI VMs and the connectors' metrics (invariant 5). It runs on `pve-2`, which is also its gateway.
Traefik and RustFS run in it, from the
pipeline (README, ct-base-01), and the names `pve`, `pbs`, `s3` and
`s3-console` point at it: WARP's Gateway through `base_service_hostnames`, and
the CI VMs through their `/etc/hosts`.

The `platform` VIPs are not VMs: they are the keepalived addresses the two
`vm-lb` VMs share, in front of HAProxy, and they always move together.
`10.10.4.10` is the public one: the API, the supervisor, and the ingress the
public tunnel and WARP reach. `10.10.4.9` is the internal one: the WARP-only
path, where `*.int.0xc0.cc` resolves for WARP clients and its 443 goes to
Traefik's `internal` entrypoint. The public tunnel only ever targets
`10.10.4.10`, so nothing from the internet reaches the internal path.
`vm-lb-01` and `vm-lb-02` run HAProxy, keepalived and the public tunnel's
cloudflared connectors. Both connectors target the public VIP, held by either
LB, so inside `platform` only the LBs reach 443 from the zone itself (#187).
The firewall cannot tell the two VIPs apart: the tunnel's own ingress, which
names only `10.10.4.10`, keeps the internet off the internal path.
`vm-rke2-01` to `vm-rke2-03` are identical RKE2 servers — control plane, etcd
and workloads together — and `vm-rke2-04` to `vm-rke2-06` are agents, workloads
only, in two pools (0xc0-labs/workspace#288). `vm-rke2-04` and `vm-rke2-05`
are the applications' (`0xc0.cc/pool=apps`) on `pve-2`, with Longhorn's disks;
`vm-rke2-06` is the sandboxes' (`0xc0.cc/pool=sandbox`, tainted
`0xc0.cc/pool=sandbox:NoSchedule`) on `pve-1`, with 10 vCPU, 32 GiB, a 150 GiB
root and no data disks, so no Longhorn. The servers are the `infra` pool. The
gVisor (0xc0-labs/workspace#266) runs on `vm-rke2-06` alone: `runsc` as a
second runtime and no SELinux label on its containers, so every pod there runs
unlabelled. The pools and the way back from gVisor are in the README, Node
pools.
`cluster` creates them all together (`modules/rke2-cluster`), so the load
balancer is deployed with the cluster; each RKE2 node, servers and agents but
`vm-rke2-06`, carries two blank data disks besides its root one. HAProxy sends the API, the
supervisor and the ingress to the servers only.

Packer builds a template on a throwaway VM, cloned from the previous template
in the chain (`packer/build-order`), named `<name>-next` at the template's
VMID plus 50, which becomes a template when the build ends. Only then is the
old template deleted and the new one cloned into its fixed VMID, under its
name: a build that fails or is cut leaves the old one in place. The build VM
lives in `ci`, where the runner that drives it can
reach it over SSH, at an address of its chain's: the chains build at once, the
templates of one chain one after the other. No machine may take them.

| Chain | Build address |
|---|---|
| `debian-13-base`, `debian-13-runner` | 10.10.1.250 |
| `rocky-10-base` | 10.10.1.251 |

A new chain takes the next free address here, as its templates' `build_ip`.
Packer cannot set a VM's firewall options, so the build VM is the one NIC
without zone filtering, for the minutes the build lasts.

## Transit matrix

The `transit` list in `terraform.tfvars`: every flow the firewall allows.
Anything not listed is denied. Every entry has a `proto` — `tcp` by default,
`udp` or `vrrp` otherwise — and `vrrp` entries carry no ports: the protocol has
none. Every rule the module creates is commented `<from> -> <to>: <note>`, so a
rule in Proxmox always traces back to its line of the matrix.

- An entry towards a **zone** becomes an inbound rule in that zone's security
  group (`zone-<vnet>`), sourced from the `from` zone's CIDR. Every guest, VM
  or container, gets its zone's group, input DROP, and its own firewall on. A
  container's rules are the same, set on its container ID.
- An entry may name **`targets`**: machines of its `to` zone, by name. It then
  opens only on them, as rules on their own firewalls beside the zone's group,
  and not on every machine of the zone, which is what an entry without `targets`
  does. `sources` narrows where traffic comes from, `targets` where it goes. A
  validation **(code)** refuses a target that is not a machine of a zone the
  entry goes to, and an entry with targets that also goes to the node or the
  internet. Traefik in `ct-base-01` is why it exists: its 443 opens from `mgmt`,
  for WARP, and from `ci`, for the runners, but not on the CI VMs, where jobs
  run code of their own. `ct-base-01` also reaches PBS on the host, 8007, as the
  one source the entry names, which is why 8007 is among the node's
  `admin_ports`: from an admin zone, the node admits no others.
- An entry towards the **node** becomes a node rule. From a control zone only
  the node's `admin_ports` (`node_firewall`) survive: `mgmt`'s admin entry
  gives it 22 and 8006 on the node; `ci` gets 8006, and no zone gets 443.
  Towards `platform`, `ci` gets 22, 6443 and 443: the last one for
  the vault repo's CI, which reaches Vault on the internal VIP (the rule opens
  443 to the whole zone, the VIPs included). From anywhere else, the entry's ports as written: 9100 from
  `platform`, for the node metrics scrape, and 8007 from `nodes`, PBS on the
  host that routes for the zones, for the guests of the other nodes. `nodes` is not a zone: it
  is the link between the nodes (`node_link.cidr`), usable as an entry's
  `from`.
- An entry towards the **internet** is egress, allowed by the outbound policy
  of every zone that has one.
- An entry with an empty `to` gives that zone's VMs an outbound DROP policy.
  Nothing uses it — every zone reaches at least the node or the internet —
  but the mechanism stays for a zone that must initiate nothing.

## Invariants

The session that makes a change checks it against this list before opening
its PR. Those marked **(code)** are also validations in
`environments/prod/variables.tf`: a plan that breaks them fails.

1. Every IP falls inside its zone and none is the host's `.1` **(code)**, and
   none lands on a reserved range.
2. No duplicate IPs in the `vms`, `cluster` and `containers` maps **(code)**,
   nor in the Ansible inventory, which mirrors them by hand.
3. Every firewall rule traces to an entry of the matrix, through the
   `zone-firewall` module, never a resource written by hand, and its comment
   is `<from> -> <to>: <note>`. A rule with no backing is a **critical**
   finding. The one thing admitted with no entry behind it is the datacenter's
   `management` set, which holds the nodes' addresses on the link (invariant
   6).
4. Every entry is `tcp`, `udp` or `vrrp`; `tcp` and `udp` entries list their
   ports, `vrrp` entries list none **(code)**. No entry has an empty `to`,
   but the mechanism — an explicit outbound DROP policy — stays available for
   a zone that must initiate nothing.
5. Nothing enters `mgmt` from another zone **(code)**, except SSH from the CI
   VMs the entry names in `sources`, never the whole `ci` zone: the pipeline
   runs the vm-access playbook (operator decision, 2026-09-29); and TCP 20241
   from `platform` to `vm-access-01` and `vm-access-02` alone, the `targets`
   the entry names, for Prometheus to read the admin tunnel's connector metrics
   (operator decision, 2026-11-26). Besides those, SSH between the two
   `vm-access` connectors, inside `mgmt`, is the only way in.
6. Every node stays on DROP, with the same rules on each: only 22 and
   8006 from `10.10.0.0/22` (22 never from `ci`), 9100 from `platform`, and
   from the internet only SSH as break-glass, on the node's public NIC alone
   (`iface` set to its `nic` in `node_links`, so no zone reaches 22 through
   it), closed by the Hetzner firewall until opened **(code)**; and 8007, which is PBS on the routing node's host, from the
   link between the nodes and from `ct-base-01` alone. The one
   other ingress is the nodes from each other: the datacenter's `management`
   set holds every address of `node_links`, and Proxmox admits its members to
   22, 8006, 3128, 5900 to 5999 and 60000 to 60050, which is what a cluster
   needs (the API, SSH, the console proxies and migration); corosync it admits
   by itself once a cluster exists. It is a set and not node rules because a
   node's rules are its own and a node that joins has none, so OpenTofu could
   not write them, while the datacenter's configuration is shared the moment it
   joins. It changes only by an address in `node_links`, which sits inside
   `node_link.cidr` **(code)**. Any other ingress to the node is a **critical**
   finding, and so is implicit admin access: `local_network` stays pointed at
   loopback.
7. No admin interface reaches the internet through the public tunnel: the
   portals, Vault and the Kubernetes API are reached only over WARP. The
   tunnel serves every name of `public_domains` (`terraform.tfvars`), but only
   a name with a public record reaches it, and external-dns (gitops) creates
   those only for the routes marked public. A portal's name never has one.
8. This document agrees with the code: every machine of the `vms`, `cluster`
   and `containers` maps is in the addressing plan, at the same address, and the
   matrix contradicts no explanation here.
9. No secret in the tree, encrypted or not: secrets live in Vault and reach
   OpenTofu and Ansible from the environment. A root's `terraform.tfvars` is
   committed and holds no secret; no other `.tfvars` file is committed.
10. Nothing the CI runners run listens on the network. Each runner instance's
    BuildKit answers on a Unix socket that only its own jobs open, and its
    builds reach the internet alone: nothing on the VM, nor inside the
    network (#203; `ansible/roles/github_runner/README.md`). A runner, or its
    BuildKit, that opens a port is a **critical** finding.
