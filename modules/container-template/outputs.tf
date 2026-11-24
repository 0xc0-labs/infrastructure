output "file_id" {
  description = "The template's volume ID, <datastore>:vztmpl/<file>, which a container takes as its operating system."
  value       = proxmox_download_file.main.id
}
