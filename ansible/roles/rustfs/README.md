# rustfs

RustFS, the S3 store that holds the OpenTofu state, in `ct-base-01`. The
interface is `meta/argument_specs.yml`; how the container is operated is in the
repo's README, ct-base-01.

| What | Where |
|---|---|
| The binary, pinned by version and checksum | `/opt/rustfs/<version>/rustfs` |
| The data, and the home of the `rustfs` user | `/var/lib/rustfs` |
| The root credentials, written by the operator | `/etc/rustfs/rustfs.env`, root, 0600 |
| The unit | `rustfs.service` |

- It listens on loopback, API `:9000` and console `:9001`: Traefik is the way in.
- The role creates no bucket and no user. The data directory brings them, copied
  by hand from the host's RustFS.
- The role never reads `rustfs.env`. It checks that it exists, is owned by root
  and is 0600, and stops with a message naming the operator's step if not.
- The unit is hardened with `ProtectSystem=full`, not `strict`: what else RustFS
  writes outside its data was not known when it was written. Tighten it once
  the first run shows what it needs.
- Bumping the version is the version and its checksum, from the release's
  `SHA256SUMS`, in `defaults/main.yml`. The unit's path changes with it, so the
  service restarts on the new binary. The old directory stays until removed by hand.
