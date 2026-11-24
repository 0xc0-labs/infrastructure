# Creating it makes Proxmox rewrite /etc/network/interfaces and run
# `ifreload -a`; an interface of the same name made by hand is adopted (#275).
resource "proxmox_network_linux_vlan" "link" {
  node_name = var.node_name
  name      = "${var.nic}.${var.vlan}"
  interface = var.nic
  vlan      = var.vlan
  address   = "${var.address}/${var.prefix_length}"
  mtu       = var.mtu
}
