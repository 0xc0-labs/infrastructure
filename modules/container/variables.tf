variable "name" {
  description = "Container name, which is its hostname, e.g. ct-base-01."
  type        = string
}

variable "node_name" {
  description = "Proxmox node."
  type        = string
}

variable "template_file_id" {
  description = "Volume ID of the LXC template, on the node's datastore: <datastore>:vztmpl/<file>."
  type        = string
}

variable "os_type" {
  description = "The template's distribution, which tells Proxmox how to configure the guest."
  type        = string
  default     = "debian"
}

variable "datastore_id" {
  description = "Datastore for the root disk. Must allow the rootdir content type."
  type        = string
}

variable "vnet" {
  description = "Bridge the container attaches to: its zone."
  type        = string
}

variable "mtu" {
  description = "The NIC's MTU. A vSwitch carries 1400 at most, so no guest may be wider than that."
  type        = number

  validation {
    condition     = var.mtu >= 576 && var.mtu <= 1400
    error_message = "mtu: between 576 and 1400, what a vSwitch carries."
  }
}

variable "ipv4_address" {
  description = "Static address in CIDR notation, inside the zone, e.g. 10.10.1.30/24."
  type        = string
}

variable "ipv4_gateway" {
  description = "Gateway: the zone's .1."
  type        = string
}

variable "dns_servers" {
  description = "Resolvers Proxmox writes into the container."
  type        = list(string)
}

variable "cores" {
  description = "vCPUs."
  type        = number
  default     = 1
}

variable "memory_mb" {
  description = "Memory in MB. The container has no swap."
  type        = number
  default     = 1024
}

variable "disk_size_gb" {
  description = "Root disk size in GB."
  type        = number
  default     = 8
}

variable "ssh_public_keys" {
  description = "Public keys authorised for root. The container has no password."
  type        = list(string)
}

variable "tags" {
  description = "Proxmox tags."
  type        = list(string)
  default     = []
}
