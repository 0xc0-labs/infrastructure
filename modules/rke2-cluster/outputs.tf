output "vms" {
  description = "Every VM of the cluster, load balancers, servers and agents, with its VMID, node, VNet and NIC MAC: the zone firewall's and the backup job's input."
  value = { for name, vm in merge(module.load_balancers, module.servers, module.agents) : name => {
    vm_id = vm.vm_id
    node  = merge(var.load_balancers.nodes, var.servers.nodes, var.agents.nodes)[name].node
    vnet  = var.vnet
    mac   = vm.mac_address
  } }
}

output "backup_vm_ids" {
  description = "The VMID of every VM of the cluster that the daily backup covers: all of them but the agents set with `backup = false`."
  value = concat(
    [for name, vm in module.load_balancers : vm.vm_id],
    [for name, vm in module.servers : vm.vm_id],
    [for name, vm in module.agents : vm.vm_id if var.agents.nodes[name].backup],
  )
}

output "load_balancers" {
  description = "The load balancers' addresses, by name."
  value       = { for name, vm in module.load_balancers : name => vm.ipv4_address }
}

output "servers" {
  description = "The RKE2 servers' addresses, by name."
  value       = { for name, vm in module.servers : name => vm.ipv4_address }
}

output "agents" {
  description = "The RKE2 agents' addresses, by name."
  value       = { for name, vm in module.agents : name => vm.ipv4_address }
}
