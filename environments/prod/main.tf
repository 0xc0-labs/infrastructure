# Every zone is a bridge over its vSwitch on every node. A node with an entry
# in `zone_gateways` holds the zone's address on it, and so routes for it.
locals {
  zone_bridges = {
    for p in setproduct(var.nodes, keys(var.zones)) : "${p[0]}/${p[1]}" => {
      node    = p[0]
      zone    = p[1]
      address = try(var.zone_gateways[p[0]][p[1]], null)
    }
  }
}

module "zone_bridge" {
  source   = "../../modules/zone-bridge"
  for_each = local.zone_bridges

  node_name     = each.value.node
  name          = each.value.zone
  nic           = var.node_links[each.value.node].nic
  vlan          = var.zones[each.value.zone].vlan
  mtu           = var.node_link.mtu
  address       = each.value.address
  prefix_length = tonumber(split("/", var.zones[each.value.zone].cidr)[1])
}

# The nodes were changed by hand, in one reload, before this root managed
# them: the bridges and their VLAN interfaces exist already (#284).
locals {
  adopted_nodes = ["pve-1", "pve-2"]
  adopted_bridges = {
    for k, b in local.zone_bridges : k => b if contains(local.adopted_nodes, b.node)
  }
}

import {
  for_each = local.adopted_bridges

  to = module.zone_bridge[each.key].proxmox_network_linux_vlan.zone
  id = "${each.value.node}:${var.node_links[each.value.node].nic}.${var.zones[each.value.zone].vlan}"
}

import {
  for_each = local.adopted_bridges

  to = module.zone_bridge[each.key].proxmox_network_linux_bridge.zone
  id = "${each.value.node}:${each.value.zone}"
}

# What the zones were before the bridges, made on the nodes already: forgotten
# without destroying, since destroying it would delete every bridge under its
# guests (#284).
removed {
  from = module.sdn

  lifecycle {
    destroy = false
  }
}

# The nodes that hold a template or run a machine.
locals {
  machine_nodes = distinct(concat(
    [for t in values(var.templates) : t.node],
    [for v in values(var.vms) : v.node],
    [for n in values(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes)) : n.node],
  ))
}

# Packer's templates are created outside OpenTofu: read them from Proxmox, on
# each of those nodes.
data "proxmox_virtual_environment_vms" "templates" {
  for_each = toset(local.machine_nodes)

  node_name = each.key

  filter {
    name   = "template"
    values = [true]
  }

  depends_on = [module.templates]
}

locals {
  # A template is found by name, never by VMID: the node that holds it and
  # its VMID. A VM on another node is cloned there and migrated (modules/vm).
  # Packer keeps one copy of each; if two nodes held one, the first by name
  # would win.
  template_copies = flatten([
    for node, d in data.proxmox_virtual_environment_vms.templates : [
      for vm in d.vms : { name = vm.name, node = node, vm_id = vm.vm_id }
    ]
  ])
  templates_by_name = {
    for name, copies in { for t in local.template_copies : t.name => t... } : name => copies[0]
  }
}

module "templates" {
  source   = "../../modules/cloud-image-template"
  for_each = var.templates

  name           = each.key
  vm_id          = each.value.vm_id
  node_name      = each.value.node
  datastore_id   = var.template_datastore
  image_url      = each.value.image_url
  image_checksum = each.value.image_checksum

  image_checksum_algorithm = each.value.checksum_algorithm
  disk_size_gb             = each.value.disk_size_gb
  bridge                   = each.value.bridge
  mtu                      = var.node_link.mtu

  # The default bridge is one of the zones.
  depends_on = [module.zone_bridge]
}

# Only the nodes this root runs on get an interface; the set below holds them all.
module "node_link" {
  source   = "../../modules/node-link"
  for_each = { for node, l in var.node_links : node => l if contains(var.nodes, node) }

  node_name     = each.key
  nic           = each.value.nic
  vlan          = var.node_link.vlan
  address       = each.value.address
  prefix_length = tonumber(split("/", var.node_link.cidr)[1])
  mtu           = var.node_link.mtu
}

# pve-2's interface was made through the API before this root managed it (#277).
import {
  to = module.node_link["pve-2"].proxmox_network_linux_vlan.link
  id = "pve-2:eno1.4000"
}

module "zero_trust" {
  source = "../../modules/zero-trust"

  account_id       = var.cloudflare_account_id
  team_name        = var.zero_trust_team
  include_networks = [var.zones_cidr]
  allowed_emails   = var.warp_allowed_emails

  github_client_id     = var.github_oauth_client_id
  github_client_secret = var.github_oauth_client_secret
  github_organization  = var.github_organization
  github_team          = var.github_admins_team

  private_hostnames    = var.base_service_hostnames
  private_hostnames_ip = var.containers["ct-base-01"].ip

  internal_domains = var.internal_domains
  internal_ip      = var.cluster.internal_vip
}

module "access_apps" {
  source   = "../../modules/access-app"
  for_each = var.access_apps

  account_id           = var.cloudflare_account_id
  name                 = each.value.name
  domain               = each.value.domain
  bypass_paths         = each.value.bypass_paths
  operator_emails      = var.warp_allowed_emails
  identity_provider_id = module.zero_trust.onetimepin_identity_provider_id
}

module "email_routing" {
  source = "../../modules/email-routing"
  # The domains are not secret; their addresses and destinations are.
  for_each = toset(nonsensitive(keys(var.email_forwards)))

  zone_name    = each.key
  destinations = var.email_destinations
  forwards     = var.email_forwards[each.key].addresses
  catch_all    = var.email_forwards[each.key].catch_all
}

# Destinations belong to the Cloudflare account, shared by all its zones.
locals {
  email_destinations_by_account = {
    for account, names in { for zone, m in module.email_routing : m.account_id => m.destinations_used... } :
    account => toset(flatten([for n in names : tolist(n)]))
  }
}

module "email_destinations" {
  source   = "../../modules/email-destinations"
  for_each = local.email_destinations_by_account

  account_id = each.key
  emails     = { for n in each.value : n => var.email_destinations[n] }
}

module "mail_domains" {
  source   = "../../modules/mail-domain"
  for_each = var.mail_domains

  zone_name       = each.key
  dkim            = each.value.dkim
  sending_records = each.value.sending_records
  dmarc           = each.value.dmarc
  report_domains  = each.value.report_domains
}

output "email_forwards_pending" {
  description = "By domain, the forwards still waiting for their destination's confirmation: they get their rule on the first apply after it."
  value       = { for zone, m in module.email_routing : zone => m.pending }
}

# Public traffic enters platform, never mgmt (docs/architecture.md, Web traffic).
module "public_tunnel" {
  source = "../../modules/cloudflare-tunnel"

  account_id = var.cloudflare_account_id
  name       = "public"
  ingress = flatten([for d in var.public_domains : [
    for h in ["*.${d}", d] : { hostname = h, service = "https://${var.cluster.vip}:443" }
  ]])
}

# No name a public zone proxies accepts TLS below 1.2 (#215).
module "zone_settings" {
  source   = "../../modules/zone-settings"
  for_each = toset(var.public_domains)

  zone_name = each.key
}

module "admin_tunnel" {
  source = "../../modules/cloudflare-tunnel"

  account_id = var.cloudflare_account_id
  name       = "admin"
  routes     = [var.zones_cidr]
}

# docs/architecture.md, The applications' files (workspace#88).
locals {
  r2_public = { for name, b in var.r2_buckets : name => b.public if b.public != null }
}

module "zone_rules" {
  source   = "../../modules/zone-rules"
  for_each = toset([for b in values(local.r2_public) : b.zone_name])

  zone_name = each.key
  cache_rules = [for name, b in local.r2_public : {
    ref         = "r2_${replace(name, "-", "_")}"
    description = "R2 bucket ${name}, at ${b.hostname}: cached"
    expression  = "http.host eq \"${b.hostname}\""
    edge_ttl    = b.edge_ttl
    browser_ttl = b.browser_ttl
  } if b.zone_name == each.key]
  response_headers = [for name, b in local.r2_public : {
    ref         = "r2_${replace(name, "-", "_")}"
    description = "R2 bucket ${name}, at ${b.hostname}: nothing it serves runs"
    expression  = "http.host eq \"${b.hostname}\""
    set = {
      "X-Content-Type-Options"  = "nosniff"
      "Content-Security-Policy" = "default-src 'none'"
    }
  } if b.zone_name == each.key]
}

module "r2_buckets" {
  source   = "../../modules/r2-bucket"
  for_each = var.r2_buckets

  account_id    = var.cloudflare_account_id
  name          = each.key
  custom_domain = each.value.public == null ? null : { hostname = each.value.public.hostname, zone_name = each.value.public.zone_name }

  # No depends_on module.zone_rules: a change to a rule would then defer the
  # zone's lookup to the apply, and the custom domain, its zone_id unknown,
  # would be replaced.
}

module "vms" {
  source   = "../../modules/vm"
  for_each = var.vms

  name      = each.key
  rebuild   = each.value.rebuild
  cpu_type  = each.value.cpu_type
  node_name = each.value.node
  # A template is missing while Packer rebuilds it. The fallback, the highest
  # VMID, never exists: a new VM fails instead of cloning another one.
  template_vm_id     = try(local.templates_by_name[each.value.template].vm_id, 2147483647)
  template_node_name = try(local.templates_by_name[each.value.template].node, null)
  datastore_id       = var.template_datastore

  vnet         = each.value.vnet
  mtu          = var.node_link.mtu
  ipv4_address = "${each.value.ip}/${split("/", var.zones[each.value.vnet].cidr)[1]}"
  ipv4_gateway = cidrhost(var.zones[each.value.vnet].cidr, 1)
  dns_servers  = var.vm_dns_servers

  cores        = each.value.cores
  memory_mb    = each.value.memory_mb
  disk_size_gb = each.value.disk_size_gb

  username        = var.vm_admin_user
  ssh_public_keys = var.vm_admin_ssh_keys
  tags            = [each.value.vnet]

  # The bridges must exist before a VM can attach to one.
  depends_on = [module.zone_bridge]
}

module "container_templates" {
  source   = "../../modules/container-template"
  for_each = var.container_templates

  node_name          = each.value.node
  datastore_id       = var.template_datastore
  url                = each.value.url
  checksum           = each.value.checksum
  checksum_algorithm = each.value.checksum_algorithm
}

module "containers" {
  source   = "../../modules/container"
  for_each = var.containers

  name             = each.key
  node_name        = each.value.node
  template_file_id = module.container_templates[each.value.template].file_id
  datastore_id     = var.template_datastore

  vnet         = each.value.vnet
  mtu          = var.node_link.mtu
  ipv4_address = "${each.value.ip}/${split("/", var.zones[each.value.vnet].cidr)[1]}"
  ipv4_gateway = cidrhost(var.zones[each.value.vnet].cidr, 1)
  dns_servers  = var.vm_dns_servers

  cores        = each.value.cores
  memory_mb    = each.value.memory_mb
  disk_size_gb = each.value.disk_size_gb

  ssh_public_keys = var.vm_admin_ssh_keys
  tags            = [each.value.vnet]

  # The bridges must exist before a container can attach to one.
  depends_on = [module.zone_bridge]
}

module "cluster" {
  source = "../../modules/rke2-cluster"

  datastore_id       = var.template_datastore
  data_datastore_ids = var.cluster.data_datastores
  vnet               = var.cluster.vnet
  mtu                = var.node_link.mtu
  cidr               = var.zones[var.cluster.vnet].cidr
  dns_servers        = var.vm_dns_servers

  # The same fallback as the vms: a missing template must not fail the plan.
  load_balancers = {
    template = {
      vm_id = try(local.templates_by_name[var.cluster.load_balancers.template].vm_id, 2147483647)
      node  = try(local.templates_by_name[var.cluster.load_balancers.template].node, null)
    }
    cores        = var.cluster.load_balancers.cores
    memory_mb    = var.cluster.load_balancers.memory_mb
    disk_size_gb = var.cluster.load_balancers.disk_size_gb
    nodes        = var.cluster.load_balancers.nodes
  }
  servers = {
    template = {
      vm_id = try(local.templates_by_name[var.cluster.servers.template].vm_id, 2147483647)
      node  = try(local.templates_by_name[var.cluster.servers.template].node, null)
    }
    cpu_type      = var.cluster.servers.cpu_type
    cores         = var.cluster.servers.cores
    memory_mb     = var.cluster.servers.memory_mb
    disk_size_gb  = var.cluster.servers.disk_size_gb
    data_disks_gb = var.cluster.servers.data_disks_gb
    nodes         = var.cluster.servers.nodes
  }
  agents = {
    template = {
      vm_id = try(local.templates_by_name[var.cluster.agents.template].vm_id, 2147483647)
      node  = try(local.templates_by_name[var.cluster.agents.template].node, null)
    }
    cpu_type      = var.cluster.agents.cpu_type
    cores         = var.cluster.agents.cores
    memory_mb     = var.cluster.agents.memory_mb
    disk_size_gb  = var.cluster.agents.disk_size_gb
    data_disks_gb = var.cluster.agents.data_disks_gb
    nodes         = var.cluster.agents.nodes
  }

  username        = var.vm_admin_user
  ssh_public_keys = var.vm_admin_ssh_keys

  # The bridges must exist before a VM can attach to one.
  depends_on = [module.zone_bridge]
}

module "zone_firewall" {
  source = "../../modules/zone-firewall"

  node_names   = var.nodes
  node_nics    = { for node, l in var.node_links : node => l.nic }
  enabled      = var.datacenter_firewall_enabled
  node_enabled = var.node_firewall_enabled
  zones        = { for vnet, z in var.zones : vnet => { alias = z.alias, cidr = z.cidr } }
  # Sources are machine names in tfvars, VMs, cluster machines or containers;
  # the module takes their addresses.
  transit = [for e in var.transit : merge(e, {
    sources = [for s in e.sources : merge(
      { for name, vm in var.vms : name => vm.ip },
      { for name, n in merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes) : name => n.ip },
      { for name, c in var.containers : name => c.ip },
    )[s]]
  })]
  node_admin     = var.node_firewall
  node_links     = { for node, l in var.node_links : node => l.address }
  node_link_cidr = var.node_link.cidr
  vms = merge(
    { for name, vm in var.vms : name => {
      vm_id = module.vms[name].vm_id
      node  = vm.node
      vnet  = vm.vnet
      mac   = module.vms[name].mac_address
    } },
    { for name, c in var.containers : name => {
      vm_id     = module.containers[name].vm_id
      node      = c.node
      vnet      = c.vnet
      mac       = module.containers[name].mac_address
      container = true
    } },
    module.cluster.vms,
  )

  depends_on = [module.vms, module.cluster, module.containers]
}

# The node's firewall was one resource per kind before it ran on every node.
moved {
  from = module.zone_firewall.proxmox_node_firewall.main
  to   = module.zone_firewall.proxmox_node_firewall.main["pve-1"]
}

moved {
  from = module.zone_firewall.proxmox_virtual_environment_firewall_rules.node
  to   = module.zone_firewall.proxmox_virtual_environment_firewall_rules.node["pve-1"]
}

module "cluster_options" {
  source = "../../modules/cluster-options"

  migration_cidr                = var.node_link.cidr
  migration_bandwidth_limit_mib = var.migration_bandwidth_limit_mib
}

# Templates stay out; Packer rebuilds them.
module "backup" {
  source = "../../modules/backup-job"

  id       = "vms-daily"
  storage  = var.backup.storage
  schedule = var.backup.schedule
  vm_ids = concat(
    [for name, vm in module.vms : vm.vm_id],
    module.cluster.backup_vm_ids,
    [for name, c in module.containers : c.vm_id],
  )
  retention = var.backup.retention
}
