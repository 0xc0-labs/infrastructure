variable "migration_cidr" {
  description = "The network guest migrations go over, as a CIDR: the link between the nodes."
  type        = string
}

variable "migration_bandwidth_limit_mib" {
  description = "Limit on the I/O of a migration, in MiB/s. The provider takes KiB/s."
  type        = number

  validation {
    condition     = var.migration_bandwidth_limit_mib > 0
    error_message = "migration_bandwidth_limit_mib: above zero."
  }
}
