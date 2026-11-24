locals {
  vnet_of = { for vnet, z in var.zones : z.alias => vnet }
  # `nodes` is the link between the nodes: an entry from it admits every node.
  cidr_of = merge({ for vnet, z in var.zones : z.alias => z.cidr }, { nodes = var.node_link_cidr })

  # Proxmox writes port ranges as a:b.
  dport = [for e in var.transit : join(",", [for p in e.ports : replace(p, "-", ":")])]

  source = [for e in var.transit : length(e.sources) > 0 ? join(",", e.sources) : lookup(local.cidr_of, e.from, "")]

  rules = {
    for vnet, z in var.zones : vnet => [
      for i, e in var.transit : {
        proto   = e.proto
        source  = local.source[i]
        dport   = local.dport[i]
        targets = e.targets
        comment = e.note == "" ? "${e.from} -> ${z.alias}" : "${e.from} -> ${z.alias}: ${e.note}"
      } if contains(e.to, z.alias)
    ]
  }
  # An entry without targets opens on every machine of the zone, through the
  # zone's group; one with targets, on those machines only, as rules of their own.
  group_rules = { for vnet, rules in local.rules : vnet => [for r in rules : r if length(r.targets) == 0] }
  groups      = { for vnet, rules in local.group_rules : vnet => rules if length(rules) > 0 }
  targeted_rules = {
    for name, m in var.vms : name => [for r in local.rules[m.vnet] : r if contains(r.targets, name)]
  }

  node_ports = [
    for e in var.transit : (
      contains(var.node_admin.admin_zones, e.from)
      ? [for p in e.ports : p if contains(var.node_admin.admin_ports, p)]
      : e.ports
    )
  ]
  node_rules = [
    for i, e in var.transit : {
      proto   = e.proto
      source  = local.source[i]
      dport   = join(",", [for p in local.node_ports[i] : replace(p, "-", ":")])
      public  = e.from == "internet"
      comment = e.note == "" ? "${e.from} -> node" : "${e.from} -> node: ${e.note}"
    } if contains(e.to, "node") && length(local.node_ports[i]) > 0
  ]

  no_egress = [for e in var.transit : local.vnet_of[e.from] if length(e.to) == 0 && contains(keys(local.vnet_of), e.from)]
}

resource "proxmox_virtual_environment_cluster_firewall" "main" {
  enabled = var.enabled
}

# Proxmox grants the network it detects as local implicit admin access to the
# node, outside any rule. An empty `management` ipset does not stop it.
resource "proxmox_virtual_environment_firewall_alias" "local_network" {
  name = "local_network"
  # A single address, as the API returns it: "/32" would diff on every plan.
  cidr    = "127.0.0.1"
  comment = "Overrides the detected network: no implicit admin access"
}

# Proxmox's built-in `management` set admits its members to a node's 22, 8006,
# 3128, 5900-5999 and 60000-60050. Why a set and not node rules: docs/zones.md,
# Invariants, 6.
resource "proxmox_virtual_environment_firewall_ipset" "management" {
  name    = "management"
  comment = "The nodes, on the link between them"

  dynamic "cidr" {
    for_each = var.node_links
    content {
      name    = cidr.value
      comment = cidr.key
    }
  }
}

resource "proxmox_virtual_environment_firewall_rules" "node" {
  for_each = toset(var.node_names)

  node_name = each.key

  dynamic "rule" {
    for_each = local.node_rules
    content {
      type   = "in"
      action = "ACCEPT"
      proto  = rule.value.proto
      source = rule.value.source == "" ? null : rule.value.source
      dport  = rule.value.dport
      # The zones reach a node over its bridges and VLAN interfaces, so an
      # entry from the internet bound to the public NIC never admits them.
      iface   = rule.value.public ? var.node_nics[each.key] : null
      comment = rule.value.comment
    }
  }
}

# Turned on only once its rules exist: without them it cuts SSH over WARP.
# Every node gets the same rules: a node's rules are its own, the datacenter's
# configuration is shared.
resource "proxmox_node_firewall" "main" {
  for_each = toset(var.node_names)

  node_name = each.key
  enabled   = var.node_enabled

  depends_on = [
    proxmox_virtual_environment_firewall_alias.local_network,
    proxmox_virtual_environment_firewall_rules.node,
  ]
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "main" {
  for_each = local.groups

  name    = "zone-${each.key}"
  comment = "Inbound rules for the ${each.key} zone, from the transit matrix"

  dynamic "rule" {
    for_each = each.value
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = rule.value.proto
      source  = rule.value.source
      dport   = rule.value.dport == "" ? null : rule.value.dport
      comment = rule.value.comment
    }
  }
}

# Recreated with the guest, keyed on its MAC (README.md).
resource "terraform_data" "vm" {
  for_each = var.vms
  input    = each.value.mac
}

resource "proxmox_virtual_environment_firewall_options" "main" {
  for_each = var.vms

  node_name    = each.value.node
  vm_id        = each.value.container ? null : each.value.vm_id
  container_id = each.value.container ? each.value.vm_id : null

  enabled       = true
  input_policy  = "DROP"
  output_policy = contains(local.no_egress, each.value.vnet) ? "DROP" : "ACCEPT"
  macfilter     = true

  lifecycle {
    replace_triggered_by = [terraform_data.vm[each.key]]
  }
}

resource "proxmox_virtual_environment_firewall_rules" "main" {
  for_each = { for name, vm in var.vms : name => vm if contains(keys(local.groups), vm.vnet) || length(local.targeted_rules[name]) > 0 }

  node_name    = each.value.node
  vm_id        = each.value.container ? null : each.value.vm_id
  container_id = each.value.container ? each.value.vm_id : null

  dynamic "rule" {
    for_each = contains(keys(local.groups), each.value.vnet) ? [each.value.vnet] : []
    content {
      security_group = proxmox_virtual_environment_cluster_firewall_security_group.main[rule.value].name
      comment        = "zone ${rule.value}"
    }
  }

  dynamic "rule" {
    for_each = local.targeted_rules[each.key]
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = rule.value.proto
      source  = rule.value.source
      dport   = rule.value.dport == "" ? null : rule.value.dport
      comment = rule.value.comment
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.vm[each.key]]
  }
}
