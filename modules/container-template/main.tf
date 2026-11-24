resource "proxmox_download_file" "main" {
  node_name          = var.node_name
  datastore_id       = var.datastore_id
  content_type       = "vztmpl"
  url                = var.url
  checksum           = var.checksum
  checksum_algorithm = var.checksum_algorithm

  # A pinned build never changes upstream (README.md).
  overwrite = false

  lifecycle {
    precondition {
      condition     = can(regex(var.checksum_algorithm == "sha256" ? "^[0-9a-f]{64}$" : "^[0-9a-f]{128}$", var.checksum))
      error_message = "checksum must be a lowercase hex digest of the length its algorithm gives."
    }
  }
}
