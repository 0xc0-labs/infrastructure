# node-link

The link between the nodes of a cluster: one VLAN interface on a node's NIC,
with an address and an MTU, from configuration. It is the vSwitch `cluster`
(`docs/zones.md`, vSwitches), what the nodes use for corosync, the API, SSH
and migration.

- The provider's `proxmox_network_linux_vlan`, not the deprecated
  `proxmox_virtual_environment_network_linux_vlan`.
- Creating it makes Proxmox rewrite `/etc/network/interfaces` and run
  `ifreload -a`. An interface of the same name made by hand is adopted; every
  hand-written line of the NIC's own stanza is kept and no guest is cut.
- One call per node: the root calls it for every node of `nodes` that has an
  entry in `node_links`.

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

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_network_linux_vlan.link](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/network_linux_vlan) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_address"></a> [address](#input\_address) | The node's address on the link. | `string` | n/a | yes |
| <a name="input_mtu"></a> [mtu](#input\_mtu) | The interface's MTU. A vSwitch carries 1400 at most. | `number` | n/a | yes |
| <a name="input_nic"></a> [nic](#input\_nic) | The node's physical NIC the VLAN rides on. | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Proxmox node the interface is made on. | `string` | n/a | yes |
| <a name="input_prefix_length"></a> [prefix\_length](#input\_prefix\_length) | The link's prefix length. | `number` | n/a | yes |
| <a name="input_vlan"></a> [vlan](#input\_vlan) | The VLAN ID of the link, between 4000 and 4091. | `number` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_name"></a> [name](#output\_name) | The interface's name, <nic>.<vlan>. |
<!-- END_TF_DOCS -->
