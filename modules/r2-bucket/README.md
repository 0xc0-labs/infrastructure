# r2-bucket

One Cloudflare R2 bucket, where an application keeps its files: one per
application and environment, named `<namespace>-<purpose>` (`payload-media`).

- **The bucket**, in western Europe (`location = "weur"`, a hint Cloudflare
  honours only when the bucket is first created). The default jurisdiction,
  not `eu`: an `eu` bucket answers only at the `.eu.` endpoint, and every
  resource naming it needs the jurisdiction too, which the provider does not
  carry through (cloudflare/terraform-provider-cloudflare#5144).
  `prevent_destroy` keeps a plan from deleting it, and R2 refuses to delete a
  bucket that still holds files.
- **Its `r2.dev` URL, off**, whatever else changes: nothing of the bucket is
  public there.
- **Its hostname**, only with `custom_domain`: a name of ours, in a zone of
  the bucket's own account, serving its files read only, over TLS 1.2 or
  later, through Cloudflare's cache. Cloudflare creates the name's DNS record
  and certificate itself. The zone's cache and header rules are not here:
  each phase has one ruleset per zone, in `zone-rules`.
  The name's TLS minimum is its own, and holds whatever its zone's
  (`zone-settings`) is, but not straight away: `media.0xc0.cc` still
  accepted TLS 1.1 minutes after its apply, and refused it the next day
  (#215).

The application reaches its bucket at `endpoint`, the account's S3 endpoint,
with an R2 token scoped to that bucket alone, which the operator creates in
the dashboard so that no secret lands in the state, and keeps in Vault.

Nothing that exists already is adopted. A bucket made by hand can be imported;
its custom domain and its `r2.dev` setting cannot, so neither is set in the
dashboard first.

## The token

The API token OpenTofu runs with needs:

| Permission (dashboard name) | API name | On | For |
|---|---|---|---|
| Workers R2 Storage: Edit | Workers R2 Storage Write | the account | the bucket, its `r2.dev` URL and its custom domain |
| Zone: Read | Zone Read | the custom domain's zone | finding the zone by name |

The custom domain needs no DNS or SSL permission, though Cloudflare creates
a record and a certificate for it: Cloudflare's API asks only for R2's own
write permission (`com.cloudflare.edge.r2.bucket.write`) to attach one.

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
| [cloudflare_r2_bucket.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/r2_bucket) | resource |
| [cloudflare_r2_custom_domain.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/r2_custom_domain) | resource |
| [cloudflare_r2_managed_domain.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/r2_managed_domain) | resource |
| [cloudflare_zone.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account holding the bucket. | `string` | n/a | yes |
| <a name="input_custom_domain"></a> [custom\_domain](#input\_custom\_domain) | The hostname of ours the bucket's files are served at, read only and through Cloudflare's cache, and its zone, in the bucket's account. null keeps the bucket private: only a token reaches its files. | <pre>object({<br/>    hostname  = string<br/>    zone_name = string<br/>  })</pre> | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Where Cloudflare places the bucket, best effort, and only when it is first created: weur is western Europe. | `string` | `"weur"` | no |
| <a name="input_name"></a> [name](#input\_name) | Bucket name, <namespace>-<purpose> (payload-media): the application's namespace, then what it keeps there. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | The account's S3 endpoint, where the application reaches the bucket with its token. |
| <a name="output_name"></a> [name](#output\_name) | The bucket's name. |
| <a name="output_public_url"></a> [public\_url](#output\_public\_url) | Where the bucket's files are served, or null for a private bucket. |
<!-- END_TF_DOCS -->
