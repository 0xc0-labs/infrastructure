# container

An LXC container from a Proxmox template (`modules/container-template`),
configured through the Proxmox API only: hostname, static address, DNS and
root's SSH keys. No SSH from the provider to the node.

- **Unprivileged**, with `nesting` on, which systemd in Debian 13 needs inside
  an unprivileged container. It starts at boot; its root disk is on the node's
  datastore, and it has no swap.
- The NIC has the Proxmox firewall **on**: zone rules only apply to a guest
  whose NIC has it. Its MTU is the link's, as a VM's.
- Root has SSH keys and no password.
- Proxmox assigns the VMID, from the numbering VMs share; nobody picks one.
- `prevent_destroy`: a container may hold state the estate depends on. Lifting
  it is a deliberate PR, set back by the next.
- A later template does not recreate the container: it ignores
  `template_file_id`.

Everything inside the container after it starts is Ansible's job.

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
| [proxmox_virtual_environment_container.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/virtual_environment_container) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cores"></a> [cores](#input\_cores) | vCPUs. | `number` | `1` | no |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore for the root disk. Must allow the rootdir content type. | `string` | n/a | yes |
| <a name="input_disk_size_gb"></a> [disk\_size\_gb](#input\_disk\_size\_gb) | Root disk size in GB. | `number` | `8` | no |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | Resolvers Proxmox writes into the container. | `list(string)` | n/a | yes |
| <a name="input_ipv4_address"></a> [ipv4\_address](#input\_ipv4\_address) | Static address in CIDR notation, inside the zone, e.g. 10.10.1.30/24. | `string` | n/a | yes |
| <a name="input_ipv4_gateway"></a> [ipv4\_gateway](#input\_ipv4\_gateway) | Gateway: the zone's .1. | `string` | n/a | yes |
| <a name="input_memory_mb"></a> [memory\_mb](#input\_memory\_mb) | Memory in MB. The container has no swap. | `number` | `1024` | no |
| <a name="input_mtu"></a> [mtu](#input\_mtu) | The NIC's MTU. A vSwitch carries 1400 at most, so no guest may be wider than that. | `number` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Container name, which is its hostname, e.g. ct-base-01. | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Proxmox node. | `string` | n/a | yes |
| <a name="input_os_type"></a> [os\_type](#input\_os\_type) | The template's distribution, which tells Proxmox how to configure the guest. | `string` | `"debian"` | no |
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | Public keys authorised for root. The container has no password. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Proxmox tags. | `list(string)` | `[]` | no |
| <a name="input_template_file_id"></a> [template\_file\_id](#input\_template\_file\_id) | Volume ID of the LXC template, on the node's datastore: <datastore>:vztmpl/<file>. | `string` | n/a | yes |
| <a name="input_vnet"></a> [vnet](#input\_vnet) | Bridge the container attaches to: its zone. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ipv4_address"></a> [ipv4\_address](#output\_ipv4\_address) | Static address, without the prefix length. |
| <a name="output_mac_address"></a> [mac\_address](#output\_mac\_address) | MAC of the NIC. New on every creation, so it tells a recreated container from the old one. |
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | VMID: containers and VMs share the numbering. |
<!-- END_TF_DOCS -->
