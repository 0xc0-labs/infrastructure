# traefik

Traefik for the estate's admin hostnames, in `ct-base-01`. The interface is
`meta/argument_specs.yml`; how the container is operated is in the repo's
README, ct-base-01.

| What | Where |
|---|---|
| The binary, pinned by version and checksum | `/opt/traefik/<version>/traefik` |
| Static configuration | `/etc/traefik/traefik.yml`, `:443` alone, the file provider |
| Routes | `/etc/traefik/dynamic/routes.yml`, watched: no restart on a change |
| The Cloudflare token | `/etc/traefik/traefik.env`, root and group `traefik`, 0640 |
| Certificates, and the home of the `traefik` user | `/var/lib/traefik` |
| The unit | `traefik.service` |

- It binds 443 as `traefik`, with `CAP_NET_BIND_SERVICE` alone. There is no
  port 80: no transit entry reaches it. The DNS challenge needs no inbound
  port, which is why it is the one in use.
- The routes are the host's Traefik's, with the node's address
  (`traefik_node_address`) in place of `127.0.0.1` for Proxmox and PBS, which
  accept self-signed certificates through a `serversTransport` that skips
  verification.
- The ACME resolver has no contact email.
- Bumping the version is the version and its checksum, from the release's
  `traefik_v<version>_checksums.txt`, in `defaults/main.yml`. The old directory
  stays until removed by hand.
