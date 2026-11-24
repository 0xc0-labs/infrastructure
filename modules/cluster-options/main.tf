resource "proxmox_cluster_options" "main" {
  migration_type            = "secure"
  migration_cidr            = var.migration_cidr
  bandwidth_limit_migration = var.migration_bandwidth_limit_mib * 1024
}
