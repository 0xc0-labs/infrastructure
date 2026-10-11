# zone-settings

The settings of one Cloudflare zone that OpenTofu decides. Today there is
one, the minimum TLS version: Cloudflare's edge refuses an older handshake for
every name the zone proxies. That is 1.2 by default, since 1.0 and 1.1 are
deprecated (RFC 8996). It is available on every plan, Free included.

A name the zone does not proxy (a DNS-only record) never reaches Cloudflare's
edge, so the setting does not apply to it. An R2 custom domain has a minimum
of its own (`r2-bucket`).

Every zone already has every setting, so creating the resource changes the
zone's value, and removing it changes nothing: the zone keeps the last value,
not Cloudflare's default. A value set by hand in the dashboard is overwritten
on the next apply.

## The token

The API token OpenTofu runs with needs, on each zone:

| Permission (dashboard name) | API name | For |
|---|---|---|
| Zone: Read | Zone Read | finding the zone by name |
| Zone Settings: Edit | Zone Settings Write | the minimum TLS version |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.12 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 5.25.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | 5.25.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_zone_setting.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/zone_setting) | resource |
| [cloudflare_zone.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_min_tls_version"></a> [min\_tls\_version](#input\_min\_tls\_version) | The lowest TLS version Cloudflare's edge accepts for the zone's proxied names. 1.0 and 1.1 are deprecated (RFC 8996). | `string` | `"1.2"` | no |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Zone the settings are for, e.g. 0xc0.cc. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
