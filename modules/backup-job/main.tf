resource "proxmox_backup_job" "main" {
  id       = var.id
  node     = var.node_name
  storage  = var.storage
  schedule = var.schedule
  vmid     = [for id in var.vm_ids : tostring(id)]

  mode          = "snapshot"
  enabled       = true
  repeat_missed = true

  prune_backups = { for k, v in var.retention : "keep-${k}" => tostring(v) if v > 0 }
}
