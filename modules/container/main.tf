# No vm_id: Proxmox assigns the next free one.
resource "proxmox_virtual_environment_container" "main" {
  node_name = var.node_name
  tags      = sort(distinct(concat(["opentofu"], var.tags)))

  # Root inside the container maps to an unprivileged user on the node.
  unprivileged  = true
  started       = true
  start_on_boot = true

  # systemd in Debian 13 needs it inside an unprivileged container.
  features {
    nesting = true
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = 0
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size_gb
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = var.os_type
  }

  # firewall = true: zone rules only apply to a NIC with the firewall on.
  network_interface {
    name     = "eth0"
    bridge   = var.vnet
    firewall = true
    mtu      = var.mtu
  }

  initialization {
    hostname = var.name

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    # No password: root takes SSH keys only.
    user_account {
      keys = var.ssh_public_keys
    }
  }

  lifecycle {
    # Only a literal is allowed. A container may hold state the rest of the
    # estate depends on.
    prevent_destroy = true

    # A new template must not recreate the container made from the old one.
    # The provider also replaces a container whose keys change; the keys reach
    # a running container through Ansible, not through the provider.
    ignore_changes = [operating_system[0].template_file_id, initialization[0].user_account]
  }
}
