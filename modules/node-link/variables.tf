variable "node_name" {
  description = "Proxmox node the interface is made on."
  type        = string
}

variable "nic" {
  description = "The node's physical NIC the VLAN rides on."
  type        = string
}

variable "vlan" {
  description = "The VLAN ID of the link, between 4000 and 4091."
  type        = number

  validation {
    condition     = var.vlan >= 4000 && var.vlan <= 4091
    error_message = "vlan: between 4000 and 4091."
  }
}

variable "address" {
  description = "The node's address on the link."
  type        = string
}

variable "prefix_length" {
  description = "The link's prefix length."
  type        = number
}

variable "mtu" {
  description = "The interface's MTU. A vSwitch carries 1400 at most."
  type        = number

  validation {
    condition     = var.mtu <= 1400
    error_message = "mtu: 1400 at most."
  }
}
