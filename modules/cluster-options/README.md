# cluster-options

The cluster's migration settings, in `/etc/pve/datacenter.cfg`: `secure`
migrations over the link between the nodes, limited in bandwidth.

- The provider's `proxmox_cluster_options`, not the deprecated
  `proxmox_virtual_environment_cluster_options`.
- Only these three settings are set. Whatever else the datacenter's options
  hold is left to Proxmox.
- Without `migration_cidr`, Proxmox migrates over the address the target
  node's name resolves to; setting it makes the network explicit.

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
| [proxmox_cluster_options.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/cluster_options) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_migration_bandwidth_limit_mib"></a> [migration\_bandwidth\_limit\_mib](#input\_migration\_bandwidth\_limit\_mib) | Limit on the I/O of a migration, in MiB/s. The provider takes KiB/s. | `number` | n/a | yes |
| <a name="input_migration_cidr"></a> [migration\_cidr](#input\_migration\_cidr) | The network guest migrations go over, as a CIDR: the link between the nodes. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
