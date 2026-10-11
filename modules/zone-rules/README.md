# zone-rules

The rules of one Cloudflare zone that are not a tunnel's nor Email Routing's:
its cache rules and its response header rules.

A zone has a single entry point ruleset per phase, holding every rule of
that phase, so this module holds the whole of each phase it manages: a rule
made in the dashboard, or by any other module, is removed on the next apply.
A phase with no rules here is left as it is. If the dashboard already made a
phase's ruleset, it is imported first, or the apply fails creating a second
one:

```sh
scripts/tofu prod import 'module.zone_rules["0xc0.cc"].cloudflare_ruleset.cache_settings[0]' 'zones/<zone id>/<ruleset id>'
```

- **Cache rules** (`http_request_cache_settings`): a response to a matching
  request is cached whatever its type, for the edge TTL at Cloudflare and the
  browser TTL in the browser, whatever the origin says.
- **Response header rules** (`http_response_headers_transform`): a response
  to a matching request gets each header set, replacing the origin's.

Each rule carries a `ref` of its own, so a plan names the rule it changes.

## The token

The API token OpenTofu runs with needs, on the zone:

| Permission (dashboard name) | API name | For |
|---|---|---|
| Zone: Read | Zone Read | finding the zone by name |
| Cache Rules: Edit | Cache Settings Write | the cache rules |
| Transform Rules: Edit | Zone Transform Rules Write | the response header rules |

Cloudflare's API schema accepts the zone permission above alone for a zone's
rulesets. Its guides ask for more: Account Rulesets: Edit and Account Filter
Lists: Edit beside Cache Rules, and Account Rulesets: Read beside Transform
Rules. If an apply is refused on a ruleset, those are what to add.

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
| [cloudflare_ruleset.cache_settings](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/ruleset) | resource |
| [cloudflare_ruleset.response_headers](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/resources/ruleset) | resource |
| [cloudflare_zone.main](https://registry.terraform.io/providers/cloudflare/cloudflare/5.25.0/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cache_rules"></a> [cache\_rules](#input\_cache\_rules) | The zone's cache rules, in order. A response to a request matching expression is cached, whatever its type and whatever the origin says: at Cloudflare for edge\_ttl seconds, in the browser for browser\_ttl. [] leaves the zone's cache rules unmanaged. | <pre>list(object({<br/>    ref         = string<br/>    description = string<br/>    expression  = string<br/>    edge_ttl    = number<br/>    browser_ttl = number<br/>  }))</pre> | `[]` | no |
| <a name="input_response_headers"></a> [response\_headers](#input\_response\_headers) | The zone's response header rules, in order. A response to a request matching expression gets every header in set, name => value, replacing any the origin sent. [] leaves the zone's response header rules unmanaged. | <pre>list(object({<br/>    ref         = string<br/>    description = string<br/>    expression  = string<br/>    set         = map(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Zone the rules are for, e.g. 0xc0.cc. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
