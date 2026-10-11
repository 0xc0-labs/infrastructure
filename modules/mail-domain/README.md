# mail-domain

The DNS records that let a provider send mail as a domain, signed and
aligned, so receivers see DKIM and DMARC pass. Written for Resend, which sends
through Amazon SES. One call per domain; the zone is found by name.

| Record | Name | Content |
|---|---|---|
| DKIM | `<selector>._domainkey.<domain>` (TXT) | the provider's public key, as it shows it |
| No other DKIM key | `*._domainkey.<domain>` (TXT) | `v=DKIM1; p=`: a selector without a record of its own has a null key |
| MAIL FROM | `<subdomain>.<domain>` (MX 10) | `feedback-smtp.<region>.amazonses.com` |
| MAIL FROM's SPF | `<subdomain>.<domain>` (TXT) | `v=spf1 include:amazonses.com ~all` |
| DMARC | `_dmarc.<domain>` (TXT) | `v=DMARC1; p=…; sp=…; adkim=…; aspf=…; rua=mailto:…` |

**The MAIL FROM is a subdomain** because the apex's MX and SPF belong to
Cloudflare Email Routing, which receives the domain's mail (`email-routing`).
SES's bounces go to the subdomain's MX, and its SPF covers only SES. Nothing
here touches the apex.

**DMARC passes even when strict.** The provider signs with DKIM as the domain
itself (`d=<domain>`), which aligns under `adkim=s`. SPF checks the MAIL FROM
subdomain, which aligns only under `aspf=r`, but DMARC needs just one aligned
pass.

A domain has one DMARC record; a receiver that finds two applies neither
(RFC 7489, 6.6.3). So a DMARC record or a wildcard DKIM record that already
exists is imported, never created beside it. Every record carries a
dashboard comment naming this module, so a hand-made one stands out.

## The token

The API token OpenTofu runs with needs, on the zone:

| Permission (dashboard name) | API name | For |
|---|---|---|
| Zone: Read | Zone Read | finding the zone by name |
| DNS: Edit | DNS Write | the records |

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
| [cloudflare_dns_record.dkim](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/dns_record) | resource |
| [cloudflare_dns_record.dkim_revoked](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/dns_record) | resource |
| [cloudflare_dns_record.dmarc](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/dns_record) | resource |
| [cloudflare_dns_record.mail_from_mx](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/dns_record) | resource |
| [cloudflare_dns_record.mail_from_spf](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/dns_record) | resource |
| [cloudflare_zone.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dkim"></a> [dkim](#input\_dkim) | The sending provider's DKIM key: its selector (resend for Resend) and the TXT value it shows for it, p=<public key>. | <pre>object({<br/>    selector = string<br/>    value    = string<br/>  })</pre> | n/a | yes |
| <a name="input_dmarc"></a> [dmarc](#input\_dmarc) | The domain's DMARC policy: p and sp, for the domain and its subdomains (none, quarantine or reject); adkim and aspf, the alignment (r relaxed, s strict); and rua, the address aggregate reports go to. | <pre>object({<br/>    p     = string<br/>    sp    = string<br/>    adkim = string<br/>    aspf  = string<br/>    rua   = string<br/>  })</pre> | n/a | yes |
| <a name="input_mail_from"></a> [mail\_from](#input\_mail\_from) | The MAIL FROM domain, a subdomain of zone\_name (send for send.0xc0.cc), and the Amazon SES region the provider sends from (Resend's, e.g. eu-west-1), whose feedback MX it points at. | <pre>object({<br/>    subdomain = string<br/>    region    = string<br/>  })</pre> | n/a | yes |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Domain the mail is sent as, a zone in Cloudflare, e.g. 0xc0.cc. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
