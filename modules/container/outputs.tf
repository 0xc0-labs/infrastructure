output "vm_id" {
  description = "VMID: containers and VMs share the numbering."
  value       = proxmox_virtual_environment_container.main.vm_id
}

output "ipv4_address" {
  description = "Static address, without the prefix length."
  value       = split("/", var.ipv4_address)[0]
}

output "mac_address" {
  description = "MAC of the NIC. New on every creation, so it tells a recreated container from the old one."
  value       = proxmox_virtual_environment_container.main.network_interface[0].mac_address
}
