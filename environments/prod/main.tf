module "sdn" {
  source = "../../modules/sdn-zone"

  zone_id = var.sdn_zone_id
  nodes   = var.nodes
  vnets   = var.zones
}

# Packer's templates are created outside OpenTofu: read them from Proxmox.
data "proxmox_virtual_environment_vms" "templates" {
  node_name = var.nodes[0]

  filter {
    name   = "template"
    values = [true]
  }

  depends_on = [module.templates]
}

locals {
  template_ids = { for vm in data.proxmox_virtual_environment_vms.templates.vms : vm.name => vm.vm_id }
}

module "templates" {
  source   = "../../modules/cloud-image-template"
  for_each = var.templates

  name           = each.key
  vm_id          = each.value.vm_id
  node_name      = var.nodes[0]
  datastore_id   = var.template_datastore
  image_url      = each.value.image_url
  image_checksum = each.value.image_checksum

  image_checksum_algorithm = each.value.checksum_algorithm
  disk_size_gb             = each.value.disk_size_gb
  bridge                   = each.value.bridge

  # The default bridge is one of the SDN VNets.
  depends_on = [module.sdn]
}

module "zero_trust" {
  source = "../../modules/zero-trust"

  account_id       = var.cloudflare_account_id
  team_name        = var.zero_trust_team
  include_networks = [var.zones_cidr]
  allowed_emails   = var.warp_allowed_emails

  private_hostnames    = var.node_web_hostnames
  private_hostnames_ip = cidrhost(var.zones["mgmt"].cidr, 1)

  internal_domains = var.internal_domains
  internal_ip      = var.cluster.internal_vip
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

# 0xc0.cc's, from before the module was called per domain.
moved {
  from = module.email_routing
  to   = module.email_routing["0xc0.cc"]
}

# The destinations, from when each zone made its own (#164). Both zones are in
# this account.
moved {
  from = module.email_routing["0xc0.cc"].cloudflare_email_routing_address.main["sergio"]
  to   = module.email_destinations["ca1599ae7852d5b4718cba351adad927"].cloudflare_email_routing_address.main["sergio"]
}

moved {
  from = module.email_routing["offby1.cc"].cloudflare_email_routing_address.main["alex"]
  to   = module.email_destinations["ca1599ae7852d5b4718cba351adad927"].cloudflare_email_routing_address.main["alex"]
}

# offby1.cc's own "sergio" was a second copy of the same mailbox: the refresh
# now finds it as the live destination above, so destroying it would destroy
# that one. Forgotten from the state, never destroyed. The two above are moved
# first, so this forgets only that one.
removed {
  from = module.email_routing.cloudflare_email_routing_address.main

  lifecycle {
    destroy = false
  }
}

module "mail_domains" {
  source   = "../../modules/mail-domain"
  for_each = var.mail_domains

  zone_name = each.key
  dkim      = each.value.dkim
  mail_from = each.value.mail_from
  dmarc     = each.value.dmarc
}

# Made by hand in the dashboard before OpenTofu held them (#219).
import {
  to = module.mail_domains["0xc0.cc"].cloudflare_dns_record.dmarc
  id = "068d993d1c3f23e994211457c96476f8/3de3338e19a17b79539142f7f216a179"
}

import {
  to = module.mail_domains["0xc0.cc"].cloudflare_dns_record.dkim_revoked
  id = "068d993d1c3f23e994211457c96476f8/9fefc80df6a55b8ccc1dd7c9f5c374cb"
}

output "email_forwards_pending" {
  description = "By domain, the forwards still waiting for their destination's confirmation: they get their rule on the first apply after it."
  value       = { for zone, m in module.email_routing : zone => m.pending }
}

# Public traffic enters platform, never mgmt. A name is public only once
# external-dns (gitops) gives it a record.
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

# The applications' files (workspace#88). A public bucket's zone caches what
# its hostname serves, and has every response to it read as data a browser
# never sniffs nor runs.
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
  node_name = var.nodes[0]
  # A template is missing while Packer rebuilds it. The fallback, the highest
  # VMID, never exists: a new VM fails instead of cloning another one.
  template_vm_id = lookup(local.template_ids, each.value.template, 2147483647)
  datastore_id   = var.template_datastore

  vnet         = each.value.vnet
  ipv4_address = "${each.value.ip}/${split("/", var.zones[each.value.vnet].cidr)[1]}"
  ipv4_gateway = cidrhost(var.zones[each.value.vnet].cidr, 1)
  dns_servers  = var.vm_dns_servers

  cores        = each.value.cores
  memory_mb    = each.value.memory_mb
  disk_size_gb = each.value.disk_size_gb

  username        = var.vm_admin_user
  ssh_public_keys = var.vm_admin_ssh_keys
  tags            = [each.value.vnet]

  # The VNets must exist before a VM can attach to one.
  depends_on = [module.sdn]
}

module "cluster" {
  source = "../../modules/rke2-cluster"

  node_name    = var.nodes[0]
  datastore_id = var.template_datastore
  vnet         = var.cluster.vnet
  cidr         = var.zones[var.cluster.vnet].cidr
  dns_servers  = var.vm_dns_servers

  # The same fallback as the vms: a missing template must not fail the plan.
  load_balancers = {
    template_vm_id = lookup(local.template_ids, var.cluster.load_balancers.template, 2147483647)
    cores          = var.cluster.load_balancers.cores
    memory_mb      = var.cluster.load_balancers.memory_mb
    disk_size_gb   = var.cluster.load_balancers.disk_size_gb
    nodes          = var.cluster.load_balancers.nodes
  }
  servers = {
    template_vm_id = lookup(local.template_ids, var.cluster.servers.template, 2147483647)
    cpu_type       = var.cluster.servers.cpu_type
    cores          = var.cluster.servers.cores
    memory_mb      = var.cluster.servers.memory_mb
    disk_size_gb   = var.cluster.servers.disk_size_gb
    data_disks_gb  = var.cluster.servers.data_disks_gb
    nodes          = var.cluster.servers.nodes
  }
  agents = {
    template_vm_id = lookup(local.template_ids, var.cluster.agents.template, 2147483647)
    cpu_type       = var.cluster.agents.cpu_type
    cores          = var.cluster.agents.cores
    memory_mb      = var.cluster.agents.memory_mb
    disk_size_gb   = var.cluster.agents.disk_size_gb
    data_disks_gb  = var.cluster.agents.data_disks_gb
    nodes          = var.cluster.agents.nodes
  }

  username        = var.vm_admin_user
  ssh_public_keys = var.vm_admin_ssh_keys

  # The VNets must exist before a VM can attach to one.
  depends_on = [module.sdn]
}

module "zone_firewall" {
  source = "../../modules/zone-firewall"

  node_name    = var.nodes[0]
  enabled      = var.datacenter_firewall_enabled
  node_enabled = var.node_firewall_enabled
  zones        = { for vnet, z in var.zones : vnet => { alias = z.alias, cidr = z.cidr } }
  # Sources are machine names in tfvars, VMs or cluster machines; the module
  # takes their addresses.
  transit = [for e in var.transit : merge(e, {
    sources = [for s in e.sources : merge(
      { for name, vm in var.vms : name => vm.ip },
      { for name, n in merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes) : name => n.ip },
    )[s]]
  })]
  node_admin = var.node_firewall
  vms = merge(
    { for name, vm in var.vms : name => {
      vm_id = module.vms[name].vm_id
      vnet  = vm.vnet
      mac   = module.vms[name].mac_address
    } },
    module.cluster.vms,
  )

  depends_on = [module.vms, module.cluster]
}

# Templates stay out; Packer rebuilds them.
module "backup" {
  source = "../../modules/backup-job"

  id        = "vms-daily"
  node_name = var.nodes[0]
  storage   = var.backup.storage
  schedule  = var.backup.schedule
  vm_ids = concat(
    [for name, vm in module.vms : vm.vm_id],
    [for name, vm in module.cluster.vms : vm.vm_id],
  )
  retention = var.backup.retention
}
