variable "node_name" {
  description = "Proxmox node the bridge is made on."
  type        = string
}

variable "name" {
  description = "The bridge's name: the zone's, the one every guest's NIC names."
  type        = string
}

variable "nic" {
  description = "The node's physical NIC the zone's VLAN rides on."
  type        = string
}

variable "vlan" {
  description = "The VLAN ID of the zone's vSwitch, between 4000 and 4091."
  type        = number

  validation {
    condition     = var.vlan >= 4000 && var.vlan <= 4091
    error_message = "vlan: between 4000 and 4091."
  }
}

variable "mtu" {
  description = "The MTU of the VLAN interface and of the bridge. A vSwitch carries 1400 at most."
  type        = number

  validation {
    condition     = var.mtu <= 1400
    error_message = "mtu: 1400 at most."
  }
}

variable "address" {
  description = "The node's address on the bridge, when it routes for the zone. Null: layer 2 only."
  type        = string
  default     = null
}

variable "prefix_length" {
  description = "The zone's prefix length. Used only with an address."
  type        = number
  default     = null
}
