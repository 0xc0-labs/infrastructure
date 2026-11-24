output "name" {
  description = "The interface's name, <nic>.<vlan>."
  value       = proxmox_network_linux_vlan.link.name
}
