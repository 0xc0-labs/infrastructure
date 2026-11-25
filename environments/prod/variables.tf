variable "nodes" {
  description = "Proxmox nodes in the cluster. What is per node (the zones' bridges, the link interfaces, the node firewall) takes all of them; every machine, template and VM firewall takes the `node` it names."
  type        = list(string)
}

variable "node_link" {
  description = "The link between the nodes: the vSwitch `cluster` (docs/zones.md, vSwitches)."
  type = object({
    vlan = number
    cidr = string
    mtu  = number
  })

  validation {
    condition     = var.node_link.vlan >= 4000 && var.node_link.vlan <= 4091
    error_message = "node_link.vlan: between 4000 and 4091, the range of Hetzner's vSwitches."
  }

  validation {
    condition     = var.node_link.mtu <= 1400
    error_message = "node_link.mtu: 1400 at most, what a vSwitch carries."
  }
}

variable "node_links" {
  description = "Every node's NIC and address on the link, keyed by node name, `nodes` or not: the datacenter's `management` set holds all of them."
  type = map(object({
    nic     = string
    address = string
  }))

  validation {
    condition     = alltrue([for l in values(var.node_links) : cidrcontains(var.node_link.cidr, l.address)])
    error_message = "Every node_links address must sit inside node_link.cidr."
  }

  validation {
    condition     = length(distinct([for l in values(var.node_links) : l.address])) == length(var.node_links)
    error_message = "No two nodes may share a node_links address."
  }

  validation {
    condition     = alltrue([for n in var.nodes : contains(keys(var.node_links), n)])
    error_message = "Every node of `nodes` needs an entry in node_links."
  }
}

variable "zones" {
  description = "The zones, keyed by bridge name: letters and digits, up to 8 characters. Each is a vSwitch, carried as `vlan`. docs/zones.md explains them."
  type = map(object({
    alias = string
    cidr  = string
    snat  = bool
    vlan  = number
  }))

  validation {
    condition     = alltrue([for z in values(var.zones) : z.vlan >= 4000 && z.vlan <= 4091])
    error_message = "Every zone's vlan: between 4000 and 4091, the range of Hetzner's vSwitches."
  }

  validation {
    condition     = length(distinct(concat([var.node_link.vlan], [for z in values(var.zones) : z.vlan]))) == length(var.zones) + 1
    error_message = "No two zones may share a vlan, and none may be node_link's."
  }

  # So that no zone lands on a reserved range (docs/zones.md).
  validation {
    condition = alltrue([
      for z in values(var.zones) :
      startswith(cidrhost(z.cidr, 0), "10.10.") && tonumber(split("/", z.cidr)[1]) >= 16
    ])
    error_message = "Every zone CIDR must sit inside 10.10.0.0/16. The reserved ranges are listed in docs/zones.md."
  }

  validation {
    condition     = alltrue([for id, z in var.zones : !(z.alias == "data" && z.snat)])
    error_message = "The data zone must not have SNAT: it initiates no connection."
  }
}

variable "zone_gateways" {
  description = "Each node's address in each zone it routes for, keyed by node then zone: the node holds it on the zone's bridge. A node with no entry has the bridges at layer 2 only."
  type        = map(map(string))

  validation {
    condition     = alltrue([for n in keys(var.zone_gateways) : contains(var.nodes, n)])
    error_message = "Every zone_gateways node must be in `nodes`."
  }

  validation {
    condition     = alltrue([for g in values(var.zone_gateways) : alltrue([for z in keys(g) : contains(keys(var.zones), z)])])
    error_message = "Every zone_gateways zone must be in `zones`."
  }

  validation {
    condition = alltrue([
      for g in values(var.zone_gateways) : alltrue([
        for z, ip in g : cidrcontains(var.zones[z].cidr, ip)
      ])
    ])
    error_message = "Every zone_gateways address must sit inside its zone."
  }

  validation {
    condition     = length(distinct(flatten([for g in values(var.zone_gateways) : values(g)]))) == length(flatten([for g in values(var.zone_gateways) : values(g)]))
    error_message = "No two zone_gateways entries may share an address."
  }
}

variable "migration_bandwidth_limit_mib" {
  description = "The cluster's limit on the I/O of a guest migration, in MiB/s. The link between the nodes is shared with every zone's traffic."
  type        = number

  validation {
    condition     = var.migration_bandwidth_limit_mib > 0
    error_message = "migration_bandwidth_limit_mib: above zero."
  }
}

variable "template_datastore" {
  description = "Datastore holding cloud images and VM templates. Must allow the import content type."
  type        = string
}

variable "node_datastores" {
  description = "The datastores each node has, by node name: `local` on both, plus `sata` on pve-2 (README, Storage `sata`)."
  type        = map(list(string))

  validation {
    condition     = alltrue([for n in var.nodes : contains(keys(var.node_datastores), n)])
    error_message = "Every node of `nodes` needs an entry in node_datastores."
  }
}

variable "templates" {
  description = "Official cloud images, imported as raw templates and keyed by template name. Packer bakes the templates VMs use from them."
  type = map(object({
    # 9000-9099: the raw images. Packer's templates take 9100-9149, and their
    # next builds that ID plus 50.
    vm_id              = number
    node               = string
    image_url          = string
    image_checksum     = string
    checksum_algorithm = optional(string, "sha512")
    # At least the image's virtual size: Proxmox never shrinks a disk.
    disk_size_gb = optional(number, 8)
    bridge       = string
  }))

  validation {
    condition     = alltrue([for t in values(var.templates) : contains(var.nodes, t.node)])
    error_message = "A template's node must be one of `nodes`."
  }
}

variable "cloudflare_account_id" {
  description = "Cloudflare account holding the tunnels, Zero Trust and the R2 buckets."
  type        = string
}

variable "zero_trust_team" {
  description = "Zero Trust team name; the team domain is <team>.cloudflareaccess.com."
  type        = string
}

variable "zones_cidr" {
  description = "Every zone, as one CIDR: what WARP carries, and what vm-access routes."
  type        = string

  validation {
    condition     = var.zones_cidr == "10.10.0.0/16"
    error_message = "zones_cidr must be 10.10.0.0/16, the supernet of every zone."
  }
}

# Not secret, but kept out of this public repo: from Vault
# (ci/infrastructure/warp).
variable "warp_allowed_emails" {
  description = "Who may enroll a WARP device, and so reach the zones."
  type        = list(string)
  sensitive   = true
}

# Not secret, but kept out of this public repo: from Vault
# (ci/infrastructure/email-routing), as JSON.
variable "email_destinations" {
  description = "Mailboxes Email Routing forwards to, by name."
  type        = map(string)
  sensitive   = true
}

# Likewise, from Vault (ci/infrastructure/email-routing, forwards). A change
# there takes a run of the apply workflow.
variable "email_forwards" {
  description = "Email Routing, by domain: its forwarded addresses (address => destination name in email_destinations), and optionally the destination of every other address."
  type = map(object({
    addresses = map(string)
    catch_all = optional(string)
  }))
  sensitive = true
}

variable "vm_admin_user" {
  description = "Admin user cloud-init creates on every VM. SSH keys only."
  type        = string
}

variable "vm_admin_ssh_keys" {
  description = "Public SSH keys authorised on every VM."
  type        = list(string)
}

variable "vm_dns_servers" {
  description = "Resolvers for every VM."
  type        = list(string)
}

variable "vms" {
  description = "The VMs, keyed by name. Their addresses follow the plan in docs/zones.md."
  type = map(object({
    node         = string
    template     = string
    vnet         = string
    ip           = string
    cores        = optional(number, 1)
    memory_mb    = optional(number, 1024)
    disk_size_gb = optional(number, 8)
    # Rocky 10 needs x86-64-v3.
    cpu_type = optional(string, "x86-64-v2-AES")
    # Bump to recreate the VM from its template. prevent_destroy, in the vm
    # module, has to be lifted in the same PR.
    rebuild = optional(number, 0)
  }))

  validation {
    condition = alltrue([
      for v in values(var.vms) :
      contains(keys(var.zones), v.vnet)
      && cidrhost("${v.ip}/${split("/", var.zones[v.vnet].cidr)[1]}", 0) == cidrhost(var.zones[v.vnet].cidr, 0)
      && !contains(flatten([for g in values(var.zone_gateways) : values(g)]), v.ip)
    ])
    error_message = "Every VM's ip must be inside its vnet's zone and must not be a node's zone_gateways address — see docs/zones.md."
  }

  validation {
    condition     = length(distinct([for v in values(var.vms) : v.ip])) == length(var.vms)
    error_message = "Two VMs share an address."
  }

  validation {
    condition     = alltrue([for v in values(var.vms) : contains(var.nodes, v.node)])
    error_message = "A VM's node must be one of `nodes`."
  }
}

variable "container_templates" {
  description = "LXC templates, keyed by name, each downloaded onto one node through the API as vztmpl content, pinned to a build and the digest Proxmox publishes for it."
  type = map(object({
    node               = string
    url                = string
    checksum           = string
    checksum_algorithm = optional(string, "sha512")
  }))

  validation {
    condition     = alltrue([for t in values(var.container_templates) : contains(var.nodes, t.node)])
    error_message = "A container template's node must be one of `nodes`."
  }
}

variable "containers" {
  description = "The LXC containers, keyed by name. Their addresses follow the plan in docs/zones.md, shared with the VMs."
  type = map(object({
    node         = string
    template     = string
    vnet         = string
    ip           = string
    cores        = optional(number, 1)
    memory_mb    = optional(number, 1024)
    disk_size_gb = optional(number, 8)
  }))

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      contains(keys(var.zones), c.vnet)
      && cidrhost("${c.ip}/${split("/", var.zones[c.vnet].cidr)[1]}", 0) == cidrhost(var.zones[c.vnet].cidr, 0)
      && !contains(flatten([for g in values(var.zone_gateways) : values(g)]), c.ip)
    ])
    error_message = "Every container's ip must be inside its vnet's zone and must not be a node's zone_gateways address — see docs/zones.md."
  }

  validation {
    condition = length(distinct(concat(
      [for v in values(var.vms) : v.ip],
      [for n in values(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes)) : n.ip],
      [var.cluster.vip, var.cluster.internal_vip],
      [for c in values(var.containers) : c.ip],
    ))) == length(var.vms) + length(var.cluster.load_balancers.nodes) + length(var.cluster.servers.nodes) + length(var.cluster.agents.nodes) + 2 + length(var.containers)
    error_message = "A container shares an address with a VM, a cluster machine or a VIP, or with another container."
  }

  validation {
    condition     = length(setintersection(keys(var.containers), concat(keys(var.vms), keys(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes))))) == 0
    error_message = "A container shares its name with a VM or a cluster machine: the transit matrix finds machines by name."
  }

  validation {
    condition     = alltrue([for c in values(var.containers) : contains(var.nodes, c.node)])
    error_message = "A container's node must be one of `nodes`."
  }

  # The template is on one node's datastore, which no other node reads.
  validation {
    condition     = alltrue([for c in values(var.containers) : contains(keys(var.container_templates), c.template) && try(var.container_templates[c.template].node, "") == c.node])
    error_message = "A container's template must be one of container_templates, downloaded onto the container's own node."
  }
}

variable "node_firewall_enabled" {
  description = "The node's own firewall and its DROP policy: it admits only what the transit matrix sends to the node."
  type        = bool
}

variable "datacenter_firewall_enabled" {
  description = "Proxmox datacenter firewall master switch. While off, no VM firewall is enforced."
  type        = bool
}

variable "base_service_hostnames" {
  description = "Hostnames Traefik in ct-base-01 serves (Proxmox, PBS, RustFS). WARP devices resolve them to the container's address."
  type        = list(string)
}

variable "transit" {
  description = "The transit matrix: every flow the firewall allows. from/to are zone aliases, node or internet; an empty to means the zone initiates nothing. proto is tcp unless stated."
  type = list(object({
    from  = string
    to    = list(string)
    proto = optional(string, "tcp")
    ports = list(string)
    # Machine names in the from zone, VMs, cluster machines or containers: the
    # entry then admits only their addresses, not the whole zone.
    sources = optional(list(string), [])
    # Machine names in a to zone: the entry then opens only on them, not on
    # every machine of the zone.
    targets = optional(list(string), [])
    note    = optional(string, "")
  }))

  validation {
    condition = alltrue([
      for e in var.transit :
      contains(["tcp", "udp", "vrrp"], e.proto)
      && (contains(["tcp", "udp"], e.proto) ? (length(e.ports) > 0 || length(e.to) == 0) : length(e.ports) == 0)
    ])
    error_message = "Every transit entry is tcp, udp or vrrp; tcp and udp entries list their ports, vrrp entries list none."
  }

  validation {
    condition     = alltrue([for e in var.transit : can(regex("^[ -~]*$", e.note))])
    error_message = "Transit notes must be plain ASCII: they become Proxmox rule comments."
  }

  validation {
    condition     = alltrue([for e in var.transit : !(e.from == "data" && length(e.to) > 0)])
    error_message = "data initiates nothing: no transit entry from data may have a destination."
  }

  # Operator decision, 2026-09-29.
  validation {
    condition = alltrue([
      for e in var.transit :
      !(contains(e.to, "mgmt") && e.from != "mgmt")
      || (e.from == "ci" && length(e.sources) > 0 && e.proto == "tcp" && length(e.ports) == 1 && tostring(e.ports[0]) == "22")
    ])
    error_message = "Nothing may initiate towards mgmt from another zone, except SSH (22) from named CI VMs (sources)."
  }

  validation {
    condition = alltrue(flatten([
      for e in var.transit : [for s in e.sources :
        (contains(keys(var.vms), s) && try(var.vms[s].vnet, "") == e.from)
        || (contains(keys(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes)), s) && var.cluster.vnet == e.from)
        || (contains(keys(var.containers), s) && try(var.containers[s].vnet, "") == e.from)
      ]
    ]))
    error_message = "Every transit source must be a VM of the vms map, a cluster machine or a container, in the entry's from zone."
  }

  # A target is a machine of a zone the entry goes to. Towards the node or the
  # internet there is no machine to narrow to: the entry would open on all.
  validation {
    condition = alltrue(flatten([
      for e in var.transit : [for t in e.targets :
        !contains(e.to, "node") && !contains(e.to, "internet")
        && contains(e.to, try(var.zones[lookup(merge(
          { for name, v in var.vms : name => v.vnet },
          { for name in keys(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes)) : name => var.cluster.vnet },
          { for name, c in var.containers : name => c.vnet },
        ), t, "")].alias, ""))
      ]
    ]))
    error_message = "Every transit target must be a machine of a zone the entry goes to (a VM, a cluster machine or a container), and an entry with targets does not go to the node or the internet."
  }

  # docs/zones.md, Invariants, 6.
  validation {
    condition     = alltrue([for e in var.transit : !(e.from == "internet" && contains(e.to, "node")) || (length(e.ports) == 1 && e.ports[0] == "22")])
    error_message = "From the internet the node accepts only SSH (22), as break-glass: the Proxmox API is reached over WARP, and the web names go to ct-base-01."
  }
}

variable "node_firewall" {
  description = "The node's DROP: from admin_zones it admits only admin_ports, whatever else an entry opens; from anywhere else, an entry's ports as written."
  type = object({
    admin_zones = list(string)
    admin_ports = list(string)
  })
}

variable "cluster" {
  description = "The RKE2 cluster and its load balancer pair, in one zone. The VIP is keepalived's, in front of HAProxy; addresses follow the plan in docs/zones.md."
  type = object({
    vnet = string
    vip  = string
    # The WARP-only path's VIP, on the same load balancers: *.int.0xc0.cc.
    internal_vip = string
    # Where each node keeps the servers' and agents' data disks. A node not
    # listed uses template_datastore, the system disks'.
    data_datastores = optional(map(string), {})
    load_balancers = object({
      template     = string
      cores        = optional(number, 1)
      memory_mb    = optional(number, 1024)
      disk_size_gb = optional(number, 10)
      nodes = map(object({
        node = string
        ip   = string
        # Bump to recreate the VM, as in vms.
        rebuild = optional(number, 0)
      }))
    })
    servers = object({
      template = string
      # RKE2 on Rocky 10, which needs x86-64-v3.
      cpu_type     = optional(string, "x86-64-v3")
      cores        = optional(number, 4)
      memory_mb    = optional(number, 12288)
      disk_size_gb = optional(number, 100)
      # Blank disks on top of the root one, scsi1 onwards.
      data_disks_gb = optional(list(number), [])
      nodes = map(object({
        node    = string
        ip      = string
        rebuild = optional(number, 0)
      }))
    })
    agents = optional(object({
      template      = optional(string, "rocky-10-base")
      cpu_type      = optional(string, "x86-64-v3")
      cores         = optional(number, 4)
      memory_mb     = optional(number, 12288)
      disk_size_gb  = optional(number, 100)
      data_disks_gb = optional(list(number), [])
      # A size set on a node replaces the pool's for that node alone; [] is
      # no data disks (the sandbox node's).
      nodes = optional(map(object({
        node          = string
        ip            = string
        rebuild       = optional(number, 0)
        cores         = optional(number)
        memory_mb     = optional(number)
        disk_size_gb  = optional(number)
        data_disks_gb = optional(list(number))
      })), {})
    }), {})
  })

  validation {
    condition = contains(keys(var.zones), var.cluster.vnet) && alltrue([
      for ip in concat([var.cluster.vip, var.cluster.internal_vip], [for n in merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes) : n.ip]) :
      cidrhost("${ip}/${split("/", var.zones[var.cluster.vnet].cidr)[1]}", 0) == cidrhost(var.zones[var.cluster.vnet].cidr, 0)
      && !contains(flatten([for g in values(var.zone_gateways) : values(g)]), ip)
    ])
    error_message = "The cluster's vips and every address must be inside its vnet's zone and must not be a node's zone_gateways address — see docs/zones.md."
  }

  validation {
    condition = alltrue([
      for n in merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes) : !contains([var.cluster.vip, var.cluster.internal_vip], n.ip)
    ]) && var.cluster.vip != var.cluster.internal_vip
    error_message = "No cluster machine may take a VIP, and the two VIPs must differ."
  }

  validation {
    condition     = alltrue([for n in values(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes)) : contains(var.nodes, n.node)])
    error_message = "A cluster machine's node must be one of `nodes`."
  }

  validation {
    condition = alltrue([
      for n, ds in var.cluster.data_datastores : contains(var.nodes, n) && contains(lookup(var.node_datastores, n, []), ds)
    ])
    error_message = "cluster.data_datastores: each key must be one of `nodes`, and its datastore one of that node's node_datastores."
  }

  validation {
    condition = length(setintersection(keys(var.vms), keys(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes)))) == 0 && length(distinct(concat(
      [for v in values(var.vms) : v.ip],
      [for n in values(merge(var.cluster.load_balancers.nodes, var.cluster.servers.nodes, var.cluster.agents.nodes)) : n.ip],
      [var.cluster.vip, var.cluster.internal_vip],
    ))) == length(var.vms) + length(var.cluster.load_balancers.nodes) + length(var.cluster.servers.nodes) + length(var.cluster.agents.nodes) + 2
    error_message = "A cluster machine or a VIP shares a name or an address with another VM."
  }
}

variable "backup" {
  description = "The daily backup of every VM to PBS: the PBS storage on the node, when it runs, and what PBS keeps."
  type = object({
    storage  = string
    schedule = string
    retention = object({
      last    = optional(number, 0)
      daily   = optional(number, 0)
      weekly  = optional(number, 0)
      monthly = optional(number, 0)
      yearly  = optional(number, 0)
    })
  })
}

variable "public_domains" {
  description = "Domains whose names the public tunnel serves. Each must be a zone in the tunnel's own Cloudflare account: a CNAME to the tunnel from another account's zone fails at the edge (1014)."
  type        = list(string)
  default     = []
}

variable "internal_domains" {
  description = "Domains of the WARP-only path: every name under them resolves to the cluster's internal_vip for WARP devices, and has no public record."
  type        = list(string)
  default     = []
}

variable "access_apps" {
  description = "Hostnames behind Cloudflare Access, keyed by a short name. The viewers are managed in the dashboard (modules/access-app/README.md); the operator is warp_allowed_emails."
  type = map(object({
    name         = string
    domain       = string
    bypass_paths = optional(list(string), [])
  }))
  default = {}
}

variable "r2_buckets" {
  description = "R2 buckets for the applications' files, keyed by name, <namespace>-<purpose>: one per application and environment. A bucket with public is served read only at public.hostname, a name in public.zone_name, through Cloudflare's cache: edge_ttl seconds at the edge, browser_ttl in the browser. One without is reached only with a token."
  type = map(object({
    public = optional(object({
      hostname    = string
      zone_name   = string
      edge_ttl    = number
      browser_ttl = number
    }))
  }))
  default = {}

  validation {
    condition = length(distinct([for b in values(var.r2_buckets) : b.public.hostname if b.public != null])) == length([
      for b in values(var.r2_buckets) : b if b.public != null
    ])
    error_message = "Two buckets share a public hostname."
  }
}

variable "mail_domains" {
  description = "Domains mail is sent as through Resend, keyed by zone: the DKIM key and the other sending records Resend's DNS page shows, and the DMARC policy. The modules/mail-domain inputs."
  type = map(object({
    dkim = object({
      selector = string
      value    = string
    })
    sending_records = list(object({
      name    = string
      type    = string
      content = string
    }))
    dmarc = object({
      p     = string
      sp    = string
      adkim = string
      aspf  = string
      rua   = string
    })
    report_domains = optional(list(string), [])
  }))
  default = {}
}
