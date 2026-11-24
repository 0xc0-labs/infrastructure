# Creating them makes Proxmox rewrite /etc/network/interfaces and run
# `ifreload -a`. Hand-written lines of a stanza (the zone's SNAT on the routing node) are
# kept by the API when it rewrites it (#284).
resource "proxmox_network_linux_vlan" "zone" {
  node_name = var.node_name
  name      = "${var.nic}.${var.vlan}"
  interface = var.nic
  vlan      = var.vlan
  mtu       = var.mtu
}

resource "proxmox_network_linux_bridge" "zone" {
  node_name = var.node_name
  name      = var.name
  ports     = [proxmox_network_linux_vlan.zone.name]
  address   = var.address == null ? null : "${var.address}/${var.prefix_length}"
  mtu       = var.mtu
}
