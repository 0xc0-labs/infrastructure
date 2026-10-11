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
| Its copy of the runner, and the job's work folder | `/opt/actions-runner/<n>`, `_work` inside |
| The job's `$HOME` | `/home/runner-<n>` |
| Its BuildKit, under RootlessKit, as `buildkit-<n>` | `github-runner-buildkit@<n>.service` |
| BuildKit's socket, the job's `$BUILDKIT_HOST` | `/run/github-runner-buildkit/<n>/buildkitd.sock` |
| BuildKit's state: snapshots, cache, temporary files | `/var/lib/github-runner-buildkit/<n>` |

Before its runner starts, as root: older copies of the runner pruned, the work
folder and the home emptied, BuildKit restarted empty, and a just-in-time
config fetched through Vault (`github-runner-jit`). When the job ends and the
runner exits: BuildKit stopped and its state removed, the work folder and the
home emptied again. `/tmp` and `/var/tmp` are the unit's own, and its
`/dev/shm` and IPC objects go when it stops. So nothing a job builds or caches
on the VM outlives it.

Nothing reaches the other instance either: the two run as different users,
neither can open the other's socket, home or work folder, and a job sees no
process but its own (`ProtectProc=invisible`), so not another's command line
nor its environment.

A BuildKit that fails to start does not stop its runner: the job that builds an
image fails, and every other job, the ones that would fix it included, still
runs.

## A run of the role, under running jobs

The role runs from the runners it configures (`playbooks/vm-ci.yml`), so an
instance may be busy while it runs, with that very run's job or any other.
A busy instance is left alone until its job ends: no restart, and nothing of
its own changes owner or moves:

- the handler restarts only the idle instances (`github-runner-restart-idle`);
- a copy of the runner is created or unpacked only when it is missing, and
  only a new copy is handed to the instance's user;
- the link to the current copy may move, but its owner is set on the link
  alone (`follow: false`): set through it, it would land on the copy a busy
  runner is running from and lock that runner out (#204);
- the busy instance picks a change up when its job ends: its unit stops,
  `github-runner-reset` hands its copy to its user, and it starts again on
  the new unit.

A change to the role keeps to this: whatever touches an instance's copy, home
or unit while it may be running a job is a bug, and check mode does not show
it when the task is skipped there.

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
- **A build shares the VM's network**: its `RUN` steps reach what the job
  reaches, and no more.
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
which the job cannot trace or signal. RootlessKit shares the VM's network
(`--net=host`) and no port: BuildKit answers on its Unix socket alone, and
nothing listens on the network that did not before.
