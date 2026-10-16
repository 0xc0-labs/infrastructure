# github_runner

The ephemeral GitHub Actions runners of the CI VMs (`vm-ci-01`, `vm-ci-02`),
and the rootless BuildKit each one builds images with. The interface is
`meta/argument_specs.yml`; this explains the shape, and what a workflow does to
build an image here.

## One instance

Each VM runs `github_runner_count` instances, two. Instance `<n>` is:

| What | Where |
|---|---|
| The runner, one job and then a fresh start, as `runner-<n>` | `github-runner@<n>.service` |
| The runner's install, root's, the same for every instance | `/opt/actions-runner/<version>` |
| Its state: what the runner writes, and the job's work folder | `/var/lib/github-runner/<n>`, `_work` inside |
| The job's `$HOME` | `/home/runner-<n>` |
| Its BuildKit, under RootlessKit, as `buildkit-<n>` | `github-runner-buildkit@<n>.service` |
| BuildKit's socket, the job's `$BUILDKIT_HOST` | `/run/github-runner-buildkit/<n>/buildkitd.sock` |
| BuildKit's state: snapshots, cache, temporary files | `/var/lib/github-runner-buildkit/<n>` |

Every instance carries the labels `github_runner_labels` (`0xc0`); the
instances in `github_runner_build_instances` (`[1]`) also carry
`github_runner_build_label` (`build`). A workflow that targets `build` gets at
most one job per VM, so two Next.js builds never share its 4 GB
(infrastructure#235), while the other instance keeps taking light jobs. The
labels are set when the runner registers, so a change reaches an instance at
its next start. To check it, after the run: `gh api
/orgs/0xc0-labs/actions/runners --jq '.runners[] | select(any(.labels[]; .name
== "build")) | .name'` lists one runner per VM.

Before its runner starts, as root: the runner versions no instance runs from
removed (`github-runner-prune`), the state directory and the home emptied
(`github-runner-reset`), BuildKit restarted empty, and a just-in-time
config fetched through Vault (`github-runner-jit`). When the job ends and the
runner exits: BuildKit stopped and its state removed, the state directory and
the home emptied again. `/tmp` and `/var/tmp` are the unit's own, and its
`/dev/shm` and IPC objects go when it stops. So nothing a job builds or caches
on the VM outlives it.

Nor does anything a job writes reach the runner that takes the next job:

- The runner takes the parent of its `bin/` as its root, and writes there.
  The unit mounts the install's `bin/` and `externals/` read only inside the
  state directory (`BindReadOnlyPaths=`), so the state directory is the
  runner's root, and the install is not the job's to change.
- The rest of the file system is read only to the job too
  (`ProtectSystem=strict`), but for the state directory, the home and its
  BuildKit's socket: what it writes is under the first two, which the next
  start empties.
- The just-in-time config is on no command line. Only root can read the file
  `github-runner-jit` leaves; systemd hands it to the runner as a credential
  (`LoadCredential=`), and `github-runner-listen` passes it in the
  environment, which the runner clears before it starts a job, so no step
  inherits it.

Nothing reaches the other instance either: the two run as different users,
neither can open the other's socket, home or work folder, and a job sees no
process but its own (`ProtectProc=invisible`), so not another's command line
nor its environment.

A BuildKit that fails to start does not stop its runner: the job that builds an
image fails, and every other job, the ones that would fix it included, still
runs.

## Memory

The VMs have 4 GB of RAM and the node has none to spare, so two settings
(`tasks/memory.yml`, only on the CI VMs: the role is not baked, and no other
play runs it) keep a job's peak from killing it:

- `vm.overcommit_memory = 1`
  (`/etc/sysctl.d/61-github-runner-memory.conf`). oxc-parser's raw transfer,
  which knip uses, maps a 6 GiB `ArrayBuffer` for each parse; it is virtual
  memory it never fills, but the default heuristic refuses a single mapping
  larger than RAM plus swap, and the job fails with `RangeError: Array buffer
  allocation failed` (#250). GitHub's runners allow it.
- A 4 GiB swapfile, `/swapfile`, enabled at boot through `/etc/fstab`, with
  `vm.swappiness = 10`: the Next.js build peaks at about 2.5 GB (payload#93)
  beside the system and BuildKit, and swap turns a peak that runs over into
  slowness instead of a hung VM (#235). The 32 GB disk has the room.

To check it, after the run: `swapon --show` lists `/swapfile` at 4G, and
`sysctl vm.overcommit_memory vm.swappiness` prints 1 and 10.

## Private names

`github_runner_hosts` puts the network's private names, such as
`vault.int.0xc0.cc`, in `/etc/hosts`: the CI VMs are not on WARP, so Gateway
does not resolve them. The entry is written twice, to `/etc/hosts` and to
`/etc/cloud/templates/hosts.debian.tmpl`. The VMs' user-data carries
`manage_etc_hosts: true`, so at every boot cloud-init renders `/etc/hosts`
from that template and drops anything written only there, and every runner
failed in its `ExecStartPre` with `Could not resolve host` after a reset
(#255). Turning `manage_etc_hosts` off in `/etc/cloud/cloud.cfg.d/` would not
win: the user-data overrides it. The template route leaves the hostname lines
cloud-init writes as they are, and the entry is in place before
`network-online.target`, which the runners wait for. An empty list removes
both blocks.

To check it, after a reboot: `getent hosts vault.int.0xc0.cc` prints the
platform's internal VIP.

## A run of the role, under running jobs

The role runs from the runners it configures (`playbooks/vm-ci.yml`), so an
instance may be busy while it runs, with that very run's job or any other.
A busy instance is left alone until its job ends: no restart, and nothing of
its own changes owner or moves:

- the handler restarts only the idle instances (`github-runner-restart-idle`);
- a new runner version unpacks beside the one a busy instance runs from, and
  goes only once no instance runs from it: `github-runner-prune` reads which
  version each running listener has mounted;
- the busy instance picks a change up when its job ends: its unit stops,
  `github-runner-reset` empties its state, and it starts again on the new
  unit.

A change to the role keeps to this: whatever touches the install an instance
runs from, or its state, home or unit, while it may be running a job is a bug
(#204), and check mode does not show it when the task is skipped there.

## A new runner release

The runner never updates itself. A just-in-time runner registers with updates
disabled (`DisableUpdate` in its `.runner`), and its install is read only
besides. GitHub refuses jobs to a runner 30 days behind its latest release:
the listener then exits 7 (`ACTIONS_RUNNER_RETURN_VERSION_DEPRECATED_EXIT_CODE`),
and its unit stays failed rather than fetching a new config every ten seconds.
Past those 30 days, no runner here takes a job, the one that would deploy a
bump included.

So each release gets an issue, until Renovate bumps it:

1. `github_runner_version` and `github_runner_tarball_sha256` in
   `defaults/main.yml`, and the version's default in `meta/argument_specs.yml`.
   The checksum is the `actions-runner-linux-x64-<version>.tar.gz` line of the
   release's notes, the same as that asset's `digest` in GitHub's API.
2. Its merge runs `playbooks/vm-ci.yml`, after approval: the idle runners
   restart onto the new version, a busy one when its job ends, and the older
   version goes with the last instance running it. The same merge rebuilds the
   `debian-13-runner` template, which bakes the install.

## Building an image

`buildctl` is on the `PATH`, and `$BUILDKIT_HOST` points it at the instance's
BuildKit, already running and empty. No Docker, no daemon of the job's own, no
root. A workflow that pushes to GHCR:

1. Writes the registry's credentials to a `DOCKER_CONFIG` of its own, under
   `$RUNNER_TEMP`, which the runner empties when the job ends. `buildctl`
   reads them there and hands them to BuildKit over its session: they never
   reach the daemon's disk. No token on a command line: `printf` is a shell
   builtin, and `base64` reads it from stdin.

   ```yaml
   - name: GHCR credentials, for this job alone
     env:
       GHCR_TOKEN: ${{ github.token }}
     run: |
       echo "DOCKER_CONFIG=$RUNNER_TEMP/docker" >> "$GITHUB_ENV"
       mkdir -m 0700 "$RUNNER_TEMP/docker"
       auth=$(printf '%s:%s' "$GITHUB_ACTOR" "$GHCR_TOKEN" | base64 -w0)
       printf '{"auths":{"ghcr.io":{"auth":"%s"}}}\n' "$auth" > "$RUNNER_TEMP/docker/config.json"
   ```

2. Builds and pushes, with the provenance (`mode=max`) and the SBOM the
   GitHub-hosted build gives, and reads the digest from the metadata file. An
   image name is lowercase; several tags go in one quoted `name`.

   ```yaml
   - name: Build and push
     env:
       IMAGE: ghcr.io/${{ github.repository }}
     run: |
       buildctl build \
         --frontend dockerfile.v0 \
         --local context=. \
         --local dockerfile=. \
         --opt filename=Dockerfile \
         --opt platform=linux/amd64 \
         --opt attest:provenance=mode=max \
         --opt attest:sbom= \
         --output "type=image,\"name=$IMAGE:sha-${GITHUB_SHA::7},$IMAGE:main\",push=true" \
         --metadata-file "$RUNNER_TEMP/build.json"
       echo "digest=$(jq -r '."containerimage.digest"' "$RUNNER_TEMP/build.json")" >> "$GITHUB_OUTPUT"
   ```

What to keep in mind:

- **Every build starts cold.** The VM keeps no cache between jobs. A cache
  that outlives the job is the workflow's choice, and lives off the VM:
  `--export-cache`/`--import-cache` with `type=registry`, or `type=gha`, for
  which `buildctl` reads `ACTIONS_RUNTIME_TOKEN` and the cache URLs from its
  environment. A `run:` step does not get those by default.
- **A secret goes in as a build secret**, `--secret id=<id>,env=<VAR>`, never as
  a build argument: `mode=max` provenance records the build arguments.
- **The SBOM scanner is an image**, `docker/buildkit-syft-scanner`, which
  BuildKit pulls from Docker Hub for every build, as it does a Dockerfile's
  base images.
- **One platform**, the VM's: no QEMU, so no emulated `linux/arm64`.
- **A build reaches the internet alone** (#203): its `RUN` steps, and
  BuildKit's pulls and pushes, go out through a network of BuildKit's own
  (Rootless, below). They resolve names, and reach registries and package
  mirrors, but nothing on the VM, not even its loopback, and nothing inside
  the network: no zone, no Vault, no node. A build that needs something
  inside gets it as a build secret or from the context, never by
  connecting to it.
- `docker buildx`, if a workflow brings it, drives the same daemon with
  `docker buildx create --driver remote "$BUILDKIT_HOST"`. The runner installs
  neither Docker nor Buildx.

## Rootless

BuildKit runs without root: RootlessKit puts it in a user namespace where
`buildkit-<n>` is root, and every other ID a build uses maps onto 65536
subordinate IDs of that user's own, from `github_runner_buildkit_subid_start`
(`/etc/subuid`, `/etc/subgid`), which no other user on the VM holds. What that
needs, and what installs it:

- `uidmap`: `newuidmap` and `newgidmap`, which map those IDs (`install`).
- `slirp4netns` and `nftables`, for BuildKit's network, below (`install`).
- `kernel.unprivileged_userns_clone = 1`, Debian's default, kept in
  `/etc/sysctl.d/60-github-runner.conf` (`install`).
- `overlayfs` in a user namespace, in the kernel since 5.11: no
  `fuse-overlayfs`. The module loads at boot
  (`/etc/modules-load.d/github-runner.conf`, `install`); without it, BuildKit
  falls back to copying every layer.
- BuildKit and RootlessKit, pinned by version and checksum, one directory per
  version under `/opt/buildkit` and `/opt/rootlesskit` (`install`): the unit
  names the version, so a bump restarts the idle runners onto it, and a busy
  one's BuildKit keeps its binaries until its job ends.

`newuidmap` is setuid, which is why BuildKit is a unit of its own: the runner,
and every job, keeps `NoNewPrivileges`, and a different user runs the daemon,
which the job cannot trace or signal.

BuildKit has a network of its own (#203). RootlessKit gives the daemon a
network namespace, connected to the VM's through `slirp4netns`, a user-mode
stack that opens each connection on the VM as `buildkit-<n>`:

- `--disable-host-loopback` keeps it off the VM's loopback. DNS still works:
  slirp's forwarder takes the namespace's queries to the VM's resolver, and
  RootlessKit points the namespace's `resolv.conf` at it (`--copy-up=/etc`).
- An nftables table per instance, `github_runner_buildkit_<n>`
  (`/etc/github-runner/buildkit-<n>.nft`), rejects every connection of
  `buildkit-<n>` to loopback, private, shared and link-local addresses, but
  DNS to the resolver. BuildKit's unit loads it before the daemon starts,
  so no build runs without it, and a busy instance keeps the rules its build
  started with. The table is the role's alone: no other rule of the VM's is
  touched, and Debian leaves `nftables.service` disabled.
- No port: BuildKit answers on its Unix socket alone, and nothing listens on
  the network that did not before.
