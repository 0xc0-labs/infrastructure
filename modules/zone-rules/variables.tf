variable "zone_name" {
  description = "Zone the rules are for, e.g. 0xc0.cc."
  type        = string
}

variable "cache_rules" {
  description = "The zone's cache rules, in order. A response to a request matching expression is cached, whatever its type and whatever the origin says: at Cloudflare for edge_ttl seconds, in the browser for browser_ttl. [] leaves the zone's cache rules unmanaged."
  type = list(object({
    ref         = string
    description = string
    expression  = string
    edge_ttl    = number
    browser_ttl = number
  }))
  default = []

  validation {
    condition     = length(distinct([for r in var.cache_rules : r.ref])) == length(var.cache_rules)
    error_message = "Every cache rule has a ref of its own."
  }

  validation {
    condition     = alltrue([for r in var.cache_rules : r.edge_ttl > 0 && r.browser_ttl > 0])
    error_message = "edge_ttl and browser_ttl are seconds, more than zero."
  }
}

variable "response_headers" {
  description = "The zone's response header rules, in order. A response to a request matching expression gets every header in set, name => value, replacing any the origin sent. [] leaves the zone's response header rules unmanaged."
  type = list(object({
    ref         = string
    description = string
    expression  = string
    set         = map(string)
  }))
  default = []

  validation {
    condition     = length(distinct([for r in var.response_headers : r.ref])) == length(var.response_headers)
    error_message = "Every response header rule has a ref of its own."
  }
}
