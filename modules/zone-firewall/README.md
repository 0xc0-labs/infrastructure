# zone-firewall

The zone firewall, filtered on each guest's NIC, and the node's own firewall.
Its input is the transit matrix (`transit` in `environments/prod/terraform.tfvars`);
the module computes every rule from it, and none is written by hand.

- One **security group per zone** (`zone-<vnet>`) with its inbound rules, one
  per matrix entry towards that zone, commented `<from> -> <to>: <note>`. Each
  rule's protocol is the entry's `proto` (`tcp` by default, `udp` or `vrrp`);
  a `vrrp` rule carries no ports.
- An entry with **`targets`** opens only on the machines it names, which are in
  its `to` zone, not on every machine of it: its rules sit on those machines'
  own firewalls, beside the zone's group, and the group does not carry it.
- Every guest, VM or container, gets its **own firewall on**: inbound DROP
  except its zone's group and the rules aimed at it; outbound ACCEPT, except a
  zone with no destination in the matrix, which gets DROP instead (none has
  one). A container's options and rules are the same, set on its container ID
  instead of a VM ID. A guest's options and rules are **recreated whenever the
  guest is**: Proxmox deletes them with it, and the provider cannot move rules
  to a new VMID in place. The trigger is the guest's NIC MAC, new on every
  creation.
- The **node** gets the matrix entries towards `node`: from an admin zone only
  its `admin_ports`, from elsewhere the entry's ports. Its DROP is switched on
  only after its rules exist. `local_network` points at loopback, so Proxmox
  grants no implicit admin access to the network it detects.
- The datacenter's **`management` IPSet** holds the nodes' addresses on the
  link between them (`node_links`), each commented with its node's name:
  Proxmox admits its members to what a cluster needs. A set and not node
  rules, because a joining node has no rules of its own (`docs/zones.md`,
  Invariants, 6).
- `enabled` is the **datacenter master switch**; `node_enabled`, the node's.
  With the first off, nothing is enforced.

Why on the NIC and not on the VNet: the node runs `pve-firewall` (iptables).
VNet-level (forward) rules only exist in the nftables `proxmox-firewall`, which
the Proxmox docs call a tech preview.

The routing node's `FORWARD` policy must be ACCEPT, as Proxmox expects. `pve-2`
has no Docker, so it is ACCEPT by default, and its forwarding comes from
`/etc/sysctl.d/90-ip-forward.conf` (`docs/architecture.md`, The node). Docker,
where it runs, would set DROP, and every VM would lose its egress once the
datacenter firewall is on.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.12 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 0.114.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.114.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_node_firewall.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/node_firewall) | resource |
| [proxmox_virtual_environment_cluster_firewall.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_cluster_firewall) | resource |
| [proxmox_virtual_environment_cluster_firewall_security_group.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_cluster_firewall_security_group) | resource |
| [proxmox_virtual_environment_firewall_alias.local_network](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_firewall_alias) | resource |
| [proxmox_virtual_environment_firewall_ipset.management](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_firewall_ipset) | resource |
| [proxmox_virtual_environment_firewall_options.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_firewall_options) | resource |
| [proxmox_virtual_environment_firewall_rules.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_firewall_rules) | resource |
| [proxmox_virtual_environment_firewall_rules.node](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_firewall_rules) | resource |
| [terraform_data.vm](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | The datacenter firewall's master switch. Nothing below is enforced while it is false. | `bool` | n/a | yes |
| <a name="input_node_admin"></a> [node\_admin](#input\_node\_admin) | From admin\_zones the node admits only admin\_ports; from anywhere else, an entry's ports as written. | <pre>object({<br/>    admin_zones = list(string)<br/>    admin_ports = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_node_enabled"></a> [node\_enabled](#input\_node\_enabled) | The node's own firewall: DROP on everything but its rules. Needs `enabled` too. | `bool` | n/a | yes |
| <a name="input_node_link_cidr"></a> [node\_link\_cidr](#input\_node\_link\_cidr) | The link between the nodes, as a CIDR. It is the source of a transit entry whose `from` is `nodes`. | `string` | n/a | yes |
| <a name="input_node_links"></a> [node\_links](#input\_node\_links) | Every node's address on the link between the nodes, keyed by node name, a node of `nodes` or not. They become the datacenter's `management` set. | `map(string)` | n/a | yes |
| <a name="input_node_names"></a> [node\_names](#input\_node\_names) | The nodes that get the node's firewall options and rules, the same on each. A VM's firewall goes on the node the VM runs on, which `vms` names. | `list(string)` | n/a | yes |
| <a name="input_transit"></a> [transit](#input\_transit) | The transit matrix, validated by the root. Each entry becomes rules commented "<from> -> <to>: <note>". sources, when not empty, narrows the source from the whole from zone to those addresses; targets, when not empty, narrows the machines of the to zone the entry opens on, by name. | <pre>list(object({<br/>    from    = string<br/>    to      = list(string)<br/>    proto   = string<br/>    ports   = list(string)<br/>    sources = list(string)<br/>    targets = list(string)<br/>    note    = string<br/>  }))</pre> | n/a | yes |
| <a name="input_vms"></a> [vms](#input\_vms) | Every guest, VMs and containers, with its VMID, node, VNet and NIC MAC. A new MAC means the guest was recreated. A container gets the same options and rules, set on its container ID. | <pre>map(object({<br/>    vm_id     = number<br/>    node      = string<br/>    vnet      = string<br/>    mac       = string<br/>    container = optional(bool, false)<br/>  }))</pre> | n/a | yes |
| <a name="input_zones"></a> [zones](#input\_zones) | Every zone, keyed by VNet ID: its alias (the name the transit matrix uses) and CIDR. | <pre>map(object({<br/>    alias = string<br/>    cidr  = string<br/>  }))</pre> | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
