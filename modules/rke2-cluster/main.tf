locals {
  prefix_length = split("/", var.cidr)[1]
  gateway       = cidrhost(var.cidr, 1)
}

module "load_balancers" {
  source   = "../vm"
  for_each = var.load_balancers.nodes

  name               = each.key
  rebuild            = each.value.rebuild
  node_name          = each.value.node
  template_vm_id     = var.load_balancers.template.vm_id
  template_node_name = var.load_balancers.template.node
  datastore_id       = var.datastore_id

  vnet         = var.vnet
  mtu          = var.mtu
  ipv4_address = "${each.value.ip}/${local.prefix_length}"
  ipv4_gateway = local.gateway
  dns_servers  = var.dns_servers

  cores        = var.load_balancers.cores
  memory_mb    = var.load_balancers.memory_mb
  disk_size_gb = var.load_balancers.disk_size_gb

  username        = var.username
  ssh_public_keys = var.ssh_public_keys
  tags            = [var.vnet, "lb"]
}

module "servers" {
  source   = "../vm"
  for_each = var.servers.nodes

  name               = each.key
  rebuild            = each.value.rebuild
  node_name          = each.value.node
  template_vm_id     = var.servers.template.vm_id
  template_node_name = var.servers.template.node
  datastore_id       = var.datastore_id
  cpu_type           = var.servers.cpu_type

  vnet         = var.vnet
  mtu          = var.mtu
  ipv4_address = "${each.value.ip}/${local.prefix_length}"
  ipv4_gateway = local.gateway
  dns_servers  = var.dns_servers

  data_datastore_id = lookup(var.data_datastore_ids, each.value.node, var.datastore_id)

  cores         = var.servers.cores
  memory_mb     = var.servers.memory_mb
  disk_size_gb  = var.servers.disk_size_gb
  data_disks_gb = var.servers.data_disks_gb

  username        = var.username
  ssh_public_keys = var.ssh_public_keys
  tags            = [var.vnet, "rke2"]
}

module "agents" {
  source   = "../vm"
  for_each = var.agents.nodes

  name               = each.key
  rebuild            = each.value.rebuild
  node_name          = each.value.node
  template_vm_id     = var.agents.template.vm_id
  template_node_name = var.agents.template.node
  datastore_id       = var.datastore_id
  cpu_type           = var.agents.cpu_type

  vnet         = var.vnet
  mtu          = var.mtu
  ipv4_address = "${each.value.ip}/${local.prefix_length}"
  ipv4_gateway = local.gateway
  dns_servers  = var.dns_servers

  data_datastore_id = lookup(var.data_datastore_ids, each.value.node, var.datastore_id)

  cores         = coalesce(each.value.cores, var.agents.cores)
  memory_mb     = coalesce(each.value.memory_mb, var.agents.memory_mb)
  disk_size_gb  = coalesce(each.value.disk_size_gb, var.agents.disk_size_gb)
  data_disks_gb = each.value.data_disks_gb != null ? each.value.data_disks_gb : var.agents.data_disks_gb

  username        = var.username
  ssh_public_keys = var.ssh_public_keys
  tags            = [var.vnet, "rke2", "rke2-agent"]
}
