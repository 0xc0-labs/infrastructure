# rke2_server

An RKE2 server on Rocky Linux. The interface is `meta/argument_specs.yml`;
this explains what it does not.

## The pod network's MTU

Canal runs flannel's VXLAN backend. Flannel sizes its tunnel by itself from
the node's interface, but the chart writes the pods' interface MTU
(`calico.vethuMTU`, 1450 by default) as a fixed number. The role sets it
from `rke2_server_canal_veth_mtu`, 1350: the guests' 1400 minus VXLAN's 50
bytes. It writes a `HelmChartConfig` for `rke2-canal` into RKE2's manifests
directory, which RKE2 applies by itself, rolling canal's DaemonSet.

The pod network's MTU follows the guests'. Change the guests' and this value
together. A pod keeps the MTU it was created with until it is recreated: a
node's pods get the new one when the node is restarted.

Check it: `kubectl -n kube-system get cm rke2-canal-config -o
jsonpath='{.data.veth_mtu}'`.
