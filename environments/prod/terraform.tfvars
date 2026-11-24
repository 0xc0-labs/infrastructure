# Secrets come from the environment, never from here.

nodes = ["pve-1", "pve-2"]

# The link between the nodes: the vSwitch `cluster` (docs/zones.md, vSwitches).
node_link = {
  vlan = 4000
  cidr = "10.20.0.0/24"
  mtu  = 1400
}

# The vSwitch is 1 Gbit and shared with every zone's traffic between the
# nodes: a migration at full speed would starve it.
migration_bandwidth_limit_mib = 60

node_links = {
  "pve-1" = { nic = "eno1", address = "10.20.0.1" }
  "pve-2" = { nic = "eno1", address = "10.20.0.2" }
}

# Keyed by bridge name, at most 8 letters and digits; each zone's `vlan` is its
# vSwitch's (docs/zones.md, Zones and vSwitches).
zones = {
  mgmt = {
    alias = "mgmt"
    cidr  = "10.10.0.0/24"
    snat  = true
    vlan  = 4001
  }
  ci = {
    alias = "ci"
    cidr  = "10.10.1.0/24"
    snat  = true
    vlan  = 4002
  }
  platform = {
    alias = "platform"
    cidr  = "10.10.4.0/24"
    snat  = true
    vlan  = 4003
  }
}

# Each node's address in each zone it routes for. pve-2 routes for every zone
# while pve-1 is away; the role goes back to pve-1 once it has rejoined
# (workspace#285).
zone_gateways = {
  "pve-2" = { mgmt = "10.10.0.1", ci = "10.10.1.1", platform = "10.10.4.1" }
}

template_datastore = "local"

# Pinned to a dated build, with the checksum the distribution publishes.
templates = {
  "debian-13-cloud" = {
    vm_id          = 9000
    node           = "pve-2"
    image_url      = "https://cloud.debian.org/images/cloud/trixie/20260914-2601/debian-13-genericcloud-amd64-20260914-2601.qcow2"
    image_checksum = "95e110dfcdbd0ed8a82a75ed9579802f9950cabf51a810dcc6388e81bc778188713878b9f28d583a0ea602fbf48b35996ae9ad37f584166d8fbd6489df248f53"
    bridge         = "mgmt"
  }
  # Rocky publishes only SHA-256.
  "rocky-10-cloud" = {
    vm_id              = 9001
    node               = "pve-2"
    # Rocky moves a release to its vault once the next one is out, and a vault URL does not move again.
    image_url          = "https://dl.rockylinux.org/vault/rocky/10.2/images/x86_64/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2"
    image_checksum     = "9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48"
    checksum_algorithm = "sha256"
    # The image's virtual size.
    disk_size_gb = 10
    bridge       = "mgmt"
  }
}

cloudflare_account_id = "ca1599ae7852d5b4718cba351adad927"
zero_trust_team       = "0xc0"
zones_cidr            = "10.10.0.0/16"

vm_admin_user = "ops"
# CI's private half is in Vault, ci/infrastructure/ssh.
vm_admin_ssh_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO0Sq1ydjDPRC82QwtxDWSxk2ci/E2bChEJCwm665nzZ sergioaten@0xc0-homelab 2026-09-22",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfmJpvE1msYS0+VYbfP2M8y0+w2DzuA7LLe5k8GvSlP ci@0xc0-homelab 2026-09-29",
]
vm_dns_servers = ["1.1.1.1", "1.0.0.1"]

# The VMs outside the cluster. The addressing plan is in docs/zones.md.
vms = {
  "vm-access-01" = {
    node      = "pve-2"
    rebuild   = 1
    template  = "debian-13-base"
    vnet      = "mgmt"
    ip        = "10.10.0.10"
    cores     = 1
    memory_mb = 1024
  }
  # One connector can be rebuilt while the other keeps admin access.
  "vm-access-02" = {
    node      = "pve-2"
    rebuild   = 2
    template  = "debian-13-base"
    vnet      = "mgmt"
    ip        = "10.10.0.20"
    cores     = 1
    memory_mb = 1024
  }
  # Two, so a job on one can rebuild the other.
  "vm-ci-01" = {
    node         = "pve-2"
    rebuild      = 1
    template     = "debian-13-runner"
    vnet         = "ci"
    ip           = "10.10.1.10"
    cores        = 2
    memory_mb    = 4096
    disk_size_gb = 32
  }
  "vm-ci-02" = {
    node         = "pve-2"
    template     = "debian-13-runner"
    vnet         = "ci"
    ip           = "10.10.1.20"
    cores        = 2
    memory_mb    = 4096
    disk_size_gb = 32
  }
}

# Proxmox's own template, pinned to its build and the sha512 it publishes
# (`pveam available --section system`), downloaded onto the node its
# containers run on.
container_templates = {
  "debian-13-standard" = {
    node     = "pve-2"
    url      = "https://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
    checksum = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  }
}

# The LXC containers, beside the VMs. The addressing plan is in docs/zones.md.
containers = {
  # The base services of the estate (workspace#285): Traefik and RustFS.
  "ct-base-01" = {
    node         = "pve-2"
    template     = "debian-13-standard"
    vnet         = "ci"
    ip           = "10.10.1.30"
    cores        = 1
    memory_mb    = 1024
    disk_size_gb = 8
  }
}

# Enforces every VM's firewall. Needs the FORWARD policy at ACCEPT on every node
# that hosts guests: pve-2 by default (no Docker), and pve-1 through Docker's
# ip-forward-no-drop once it hosts guests again (docs/architecture.md, The node).
datacenter_firewall_enabled = true

# The Hetzner Rescue system is the way back in.
node_firewall_enabled = true

# Served by Traefik in ct-base-01.
base_service_hostnames = ["pve.0xc0.cc", "pbs.0xc0.cc", "s3.0xc0.cc", "s3-console.0xc0.cc"]

cluster = {
  vnet = "platform"
  # keepalived's; no VM takes it.
  vip = "10.10.4.10"
  # The WARP-only path (operator decision, 2026-09-30): the public tunnel
  # never comes here.
  internal_vip = "10.10.4.9"
  load_balancers = {
    template = "debian-13-base"
    nodes = {
      "vm-lb-01" = { node = "pve-2", ip = "10.10.4.11" }
      "vm-lb-02" = { node = "pve-2", ip = "10.10.4.12" }
    }
  }
  servers = {
    template = "rocky-10-base"
    # The data disks are Longhorn's, joined by LVM (the longhorn_node role).
    disk_size_gb  = 50
    data_disks_gb = [100, 100]
    nodes = {
      "vm-rke2-01" = { node = "pve-2", ip = "10.10.4.21", rebuild = 1 }
      "vm-rke2-02" = { node = "pve-2", ip = "10.10.4.22", rebuild = 1 }
      "vm-rke2-03" = { node = "pve-2", ip = "10.10.4.23", rebuild = 1 }
    }
  }
  # Workers only (operator decision, 2026-09-30): etcd stays with the servers.
  agents = {
    template      = "rocky-10-base"
    disk_size_gb  = 50
    data_disks_gb = [100, 100]
    nodes = {
      "vm-rke2-04" = { node = "pve-2", ip = "10.10.4.24" }
    }
  }
}

# Every flow the firewall allows (docs/zones.md, Transit matrix).
transit = [
  { from = "mgmt", to = ["mgmt"], ports = [22], note = "between the vm-access connectors; a WARP session can leave from either one" },
  { from = "mgmt", to = ["ci"], ports = [22], note = "admin SSH, through the vm-access tunnel" },
  { from = "mgmt", to = ["platform"], ports = [22, 80, 443, 6443, 8200], note = "admin: SSH, both VIPs over WARP (443; 80 only redirects, on the public one), the Kubernetes API, Vault" },
  { from = "mgmt", to = ["node"], ports = [22, 8006], note = "admin: SSH and the Proxmox API, through the vm-access tunnel" },
  { from = "ci", to = ["platform"], ports = [22, 443, 6443], note = "the runner: SSH to configure the VMs, Vault on the internal VIP, and the Kubernetes API" },
  # The one way into mgmt from another zone (operator decision, 2026-09-29).
  { from = "ci", to = ["mgmt"], ports = [22], sources = ["vm-ci-01", "vm-ci-02"], note = "the pipeline's playbooks, from the CI VMs only" },
  { from = "ci", to = ["ci"], ports = [22], sources = ["vm-ci-01", "vm-ci-02"], note = "the pipeline's playbooks, between the CI VMs" },
  { from = "ci", to = ["node"], ports = [8006], note = "the Proxmox API, for the pipeline. NEVER 22 towards the node from ci" },
  { from = "mgmt", to = ["ci"], ports = [443], targets = ["ct-base-01"], note = "Traefik in ct-base-01 (Proxmox UI, PBS, RustFS), over WARP" },
  { from = "ci", to = ["ci"], ports = [443], targets = ["ct-base-01"], note = "the runners towards RustFS and the Proxmox API, through Traefik in ct-base-01" },
  { from = "platform", to = ["platform"], ports = ["2379-2381", 6443, 9099, 9345, 10250, 10257, 10259, "30000-32767"], note = "the cluster: etcd and its metrics, API, Canal health, supervisor, kubelet, controller-manager and scheduler metrics, NodePorts; the LB towards the nodes" },
  { from = "platform", to = ["platform"], proto = "udp", ports = [8472], note = "Canal VXLAN between the cluster nodes" },
  { from = "platform", to = ["platform"], proto = "vrrp", ports = [], note = "keepalived between the two LB VMs" },
  { from = "platform", to = ["platform"], ports = [443], sources = ["vm-lb-01", "vm-lb-02"], note = "the public tunnel's connectors towards the public VIP, whichever LB holds it" },
  { from = "platform", to = ["node"], ports = [9100], note = "node metrics" },
  { from = "platform", to = ["internet"], ports = [443], note = "egress, alerts to the phone among it" },
  { from = "internet", to = ["node"], ports = [22], note = "break-glass SSH, key-only; the Hetzner firewall keeps it closed until opened" },
  { from = "nodes", to = ["node"], ports = [8007], note = "PBS on the host that routes for the zones, for the guests of the other nodes" },
  { from = "ci", to = ["node"], ports = [8007], sources = ["ct-base-01"], note = "Traefik in ct-base-01 towards PBS on the host" },
]

# From the admin zones the node admits only these ports, whatever an entry
# opens.
node_firewall = {
  admin_zones = ["mgmt", "ci"]
  admin_ports = [22, 8006, 8007]
}

# Every VM, to PBS on the Storage Box (operator decision, 2026-09-29).
backup = {
  storage  = "sbox"
  schedule = "03:00"
  retention = {
    daily   = 7
    weekly  = 4
    monthly = 6
  }
}

# Operator decision, 2026-09-29. Every zone is in the tunnel's own account.
public_domains = ["0xc0.cc", "offby1.cc", "artistlabco.com"]

# The WARP-only path's names (operator decision, 2026-09-30).
internal_domains = ["int.0xc0.cc"]

# Behind Cloudflare Access, with viewers managed in the dashboard
# (modules/access-app/README.md). Stripe's webhook skips the login: the front
# checks its signature (artistlabco.com#40).
access_apps = {
  artistlabco-com-staging = {
    name         = "artistlabco.com staging"
    domain       = "staging.artistlabco.com"
    bypass_paths = ["/api/stripe/webhook"]
  }
  # Strapi's admin, public for editors who need no WARP: no bypass, since
  # Stripe's webhook reaches the front, not Strapi (workspace#202).
  artistlabco-com-cms = {
    name   = "artistlabco.com cms"
    domain = "cms.artistlabco.com"
  }
  artistlabco-com-staging-cms = {
    name   = "artistlabco.com staging cms"
    domain = "cms-staging.artistlabco.com"
  }
}

# docs/architecture.md, The applications' files (workspace#88).
r2_buckets = {
  # artistlabco.com's Strapi (workspace#202).
  artistlabco-com-media = {
    public = {
      hostname    = "media.artistlabco.com"
      zone_name   = "artistlabco.com"
      edge_ttl    = 604800 # 7 days
      browser_ttl = 86400  # 1 day
    }
  }
  artistlabco-com-staging-media = {}
  # Gated resources (workspace#168): private, downloads go by signed URL.
  artistlabco-com-resources         = {}
  artistlabco-com-staging-resources = {}
}

# Mail sent as these domains, through Resend (workspace#92), as its DNS page
# shows them, with tracking off: no links record. The DMARC policy is the
# operator's (#219).
mail_domains = {
  "0xc0.cc" = {
    dkim = {
      selector = "resend"
      value    = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDSmgzcZxX1PDQlrRm7f0ZpKS0Gno3OauyEtax0WLVIfY8TryIC3jOqMi2+AmXBEASoOSRpWNn+3O0uKs4xMlwy7kx4tSYqZNjFkh3P0KZC4QpDBwXbM6diWe2whtf+WXlE3jU1Tau0lNVYgz1nGw2WcB2Ydi1bAjK3bpqk2D5vSwIDAQAB"
    }
    sending_records = [
      { name = "rsend", type = "CNAME", content = "rsend-euw1.forge.rmta.net" },
      { name = "send", type = "CNAME", content = "send.forge.rmta.net" },
    ]
    dmarc = {
      p     = "reject"
      sp    = "reject"
      adkim = "s"
      aspf  = "s"
      rua   = "dmarc@0xc0.cc"
    }
    # artistlabco.com's reports come to this mailbox too (#240).
    report_domains = ["artistlabco.com"]
  }
  "artistlabco.com" = {
    dkim = {
      selector = "resend"
      value    = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDNigNzM6RFFi4DObgBqvJOKB4MixEB0NDVQCTDFm8iRxJQE7xT5rGgI1paIIZDpCoAa5bniamzOxCG5A0bY7eVsrZ5iv9uxM/qfSWniTpyrOimJQcnGIphypWbh/TlhSUHFNagvgASjIxzkfJ4EqgkRa12CfzCpQDXgA4yndmyYQIDAQAB"
    }
    sending_records = [
      { name = "rsend", type = "CNAME", content = "rsend-euw1.forge.rmta.net" },
      { name = "send", type = "CNAME", content = "send.forge.rmta.net" },
    ]
    dmarc = {
      p     = "reject"
      sp    = "reject"
      adkim = "s"
      aspf  = "s"
      rua   = "dmarc@0xc0.cc"
    }
  }
}
