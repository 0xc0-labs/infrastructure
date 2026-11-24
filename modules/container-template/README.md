# container-template

An LXC template, downloaded onto a node through the Proxmox API as `vztmpl`
content: Proxmox fetches the URL itself and checks the digest, so nothing goes
over SSH to the node.

- The template is a **pinned build**, with the checksum Proxmox publishes for it
  (`pveam available --section system` on a node lists them). A newer build is a
  new URL and a new checksum, never a `latest` link.
- `overwrite = false`: a pinned build never changes upstream, so the file is
  not fetched again.
- A template sits on one node's datastore: a container runs from the template
  of its own node.

A container that uses it ignores a later template (`modules/container`).

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
| [proxmox_download_file.main](https://registry.terraform.io/providers/bpg/proxmox/0.114.0/docs/resources/download_file) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_checksum"></a> [checksum](#input\_checksum) | The digest the distribution publishes for the template, lowercase hex. | `string` | n/a | yes |
| <a name="input_checksum_algorithm"></a> [checksum\_algorithm](#input\_checksum\_algorithm) | The algorithm of checksum. | `string` | `"sha512"` | no |
| <a name="input_datastore_id"></a> [datastore\_id](#input\_datastore\_id) | Datastore that takes the template. Must allow the vztmpl content type. | `string` | n/a | yes |
| <a name="input_node_name"></a> [node\_name](#input\_node\_name) | Proxmox node the template is downloaded onto: a container is created from a template on its own node's datastore. | `string` | n/a | yes |
| <a name="input_url"></a> [url](#input\_url) | Where Proxmox downloads the template from: a pinned build, never a latest link. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_file_id"></a> [file\_id](#output\_file\_id) | The template's volume ID, <datastore>:vztmpl/<file>, which a container takes as its operating system. |
<!-- END_TF_DOCS -->
