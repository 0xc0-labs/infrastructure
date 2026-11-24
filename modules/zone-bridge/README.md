# zone-bridge

One zone on one node: the VLAN interface on the node's NIC (the zone's
vSwitch) and the Linux bridge named as the zone, with that interface as its
only port, both at the zone's MTU. The bridge carries an address only when the
node routes for the zone (`zone_gateways`); otherwise it is layer 2 only and
its guests' gateway is another node's, across the vSwitch.

- The provider's `proxmox_network_linux_vlan` and `proxmox_network_linux_bridge`,
  as `node-link`.
- The zone's SNAT and conntrack lines on the routing node are hand-written in
  its bridge stanza: the bridge resource has no free line, and the API keeps
  what it did not write (`docs/zones.md`, Zones).
- One call per zone per node: the root calls it for every node of `nodes` and
  every zone.

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
| [proxmox_network_linux_bridge.zone](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/network_linux_bridge) | resource |
| [proxmox_network_linux_vlan.zone](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/network_linux_vlan) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_address"></a> [address](#input\_address) | The node's address on the bridge, when it routes for the zone. Null: layer 2 only. | `string` | `null` | no |
| <a name="input_mtu"></a> [mtu](#input\_mtu) | The MTU of the VLAN interface and of the bridge. A vSwitch carries 1400 at most. | `number` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The bridge's name: the zone's, the one every guest's NIC names. | `string` | n/a | yes |
| <a name="input_nic"></a> [nic](#input\_nic) | The node's physical NIC the zone's VLAN rides on. | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Proxmox node the bridge is made on. | `string` | n/a | yes |
| <a name="input_prefix_length"></a> [prefix\_length](#input\_prefix\_length) | The zone's prefix length. Used only with an address. | `number` | `null` | no |
| <a name="input_vlan"></a> [vlan](#input\_vlan) | The VLAN ID of the zone's vSwitch, between 4000 and 4091. | `number` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_name"></a> [name](#output\_name) | The bridge's name. |
<!-- END_TF_DOCS -->
