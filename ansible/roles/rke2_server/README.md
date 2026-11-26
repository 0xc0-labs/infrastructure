# rke2_server

An RKE2 server on Rocky Linux. The interface is `meta/argument_specs.yml`;
this explains what it does not.

## The pod network's MTU

Canal runs flannel's VXLAN backend. Flannel sizes its tunnel by itself from
the node's interface, but the chart writes the pods' interface MTU
(`calico.vethuMTU`, 1450 by default) as a fixed number. The role sets it
from `rke2_server_canal_veth_mtu`, 1350: the guests' 1400 minus VXLAN's 50
bytes. It writes a `HelmChartConfig` for `rke2-canal` into RKE2's manifests
directory, which RKE2 applies by itself, into a config map. That does not roll
canal's DaemonSet: each pod copies the MTU to the node's CNI file only when it
starts. So when the file changes, the role waits for the config map to hold
the new value, stamps it on the DaemonSet's pod template as the annotation
`0xc0.cc/veth-mtu`, which rolls it once for the cluster, and waits for the
rollout. The servers after the first find it stamped and change nothing.

The pod network's MTU follows the guests'. Change the guests' and this value
together. A pod keeps the MTU it was created with until it is recreated: a
node's pods get the new one when the node is restarted.

Check it: `kubectl -n kube-system get cm rke2-canal-config -o
jsonpath='{.data.veth_mtu}'`.

## The API server's authentication configuration

The API server starts with `--authentication-config`, a file the role writes
at `/var/lib/rancher/rke2/server/etc/authentication-config.yaml`
(`AuthenticationConfiguration`, `apiserver.config.k8s.io/v1`). Its `jwt` list
comes from `rke2_server_authentication_jwt`, empty by default: no issuer is
trusted, and client certificates and service account tokens work as before.

The file sits beside `egress-selector-config.yaml`, in the directory the API
server's pod mounts whole, so a file replaced later is still the one the pod
sees, and it carries the same SELinux type (the role checks it). The API
server watches it and reloads it without a restart: writing the file never
restarts `rke2-server`. Only the argument in `config.yaml` did, once. A file it
cannot load is ignored and the last good one kept, so a mistake is not an
outage, and does not show as a failed run either.

After a restart the role checks that the server loaded this very file: the
API server sets
`apiserver_authentication_config_controller_last_config_info{hash="sha256:…"}`
when it starts, and again after each reload, with the SHA-256 of the file's
bytes, and the role compares it with the file's checksum. Without the
argument the metric is absent, so a server that came back without it fails
the play. The `automatic_reload_*` metrics are not used: they are set only
when the file changes while the server runs. The check reads
`/metrics` through `/etc/rancher/rke2/rke2.yaml`, which points at the
server's own `127.0.0.1:6443`, never at the load balancer. After a reload,
with no restart, the same metric shows the new hash:
`kubectl get --raw /metrics | grep authentication_config_controller`.

### Who it trusts

`rke2_server_authentication_jwt` is set for the cluster in
`inventory/group_vars/platform.yml`: one authenticator, for the Cloudflare
Access application for the cluster (the output `access_oidc_issuers.kubernetes`
of the OpenTofu root; the audience is the client ID, the last segment of the
issuer's URL). Whoever holds a token it issued is the user of the token's
`email`, and every such user is in the group `admins`, which gitops binds to
`cluster-admin`. The group is a constant because Cloudflare's token carries no
team: the application admits only the team `0xc0-labs/admins` and the
operator's emails (0xc0-labs/workspace#310), so being admitted is being an
admin. Three rules back it: a token with no email is refused, and so is a
username starting with `system:`, which Kubernetes reserves for its own. The
third, `claims.?email_verified.orValue(true) == true`, is there because
Kubernetes refuses a file whose username uses `claims.email` without naming
`claims.email_verified`; Cloudflare's token carries no such claim, so it passes
on the default.

Changing the list restarts nothing. The play waits up to two minutes for the
hash of the new file, the API server's own limit (it watches the file and
re-reads it every minute). If it does not come, the play fails and names
`apiserver_authentication_config_controller_automatic_reloads_total{status="failure"}`,
which moves when the API server could not load the file and kept the old one.
