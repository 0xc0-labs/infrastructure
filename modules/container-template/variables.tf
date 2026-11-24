variable "node_name" {
  description = "Proxmox node the template is downloaded onto: a container is created from a template on its own node's datastore."
  type        = string
}

variable "datastore_id" {
  description = "Datastore that takes the template. Must allow the vztmpl content type."
  type        = string
}

variable "url" {
  description = "Where Proxmox downloads the template from: a pinned build, never a latest link."
  type        = string
}

variable "checksum" {
  description = "The digest the distribution publishes for the template, lowercase hex."
  type        = string
}

variable "checksum_algorithm" {
  description = "The algorithm of checksum."
  type        = string
  default     = "sha512"
}
