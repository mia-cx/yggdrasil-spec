# NetBird operator

Argo CD deploys the NetBird operator `0.8.0` Helm chart from the upstream OCI
repository. It also applies the `k8s-routers` NetworkRouter, which runs four
routing pods. A `DoNotSchedule` topology spread keeps at most two pods per
node. Pod DNS stays on CoreDNS and the pods use no host networking.

Create the namespace and externally managed Secret before the first sync:

```bash
kubectl create namespace netbird-operator --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic netbird-mgmt-api-key -n netbird-operator \
  --from-literal=NB_API_KEY="$(cat ~/.config/yggdrasil/netbird-primary.pat)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

The operator looks up the referenced NetBird DNS zone by Name and builds
records from that Name. Create the zone first with both Name and domain set
to `svc.olympus.yggdrasil.mia.cx`. Its distribution group is `netbird-enroll`
(the API rejects an empty list).

The sidecar-injection pod webhook only matches namespaces labelled
`netbird.io/sidecar-injection=enabled`.

## No NetBird client on K3s nodes

K3s hosts run no NetBird client. The client's nftables rules crash k3s's
bundled kube-router netpol controller (`cmp sreg undef`,
[kube-router#1788](https://github.com/cloudnativelabs/kube-router/issues/1788),
[k3s#11493](https://github.com/k3s-io/k3s/issues/11493)), and with two etcd
members one crashing node takes the cluster down. Node SSH goes through the
`olympus-lan` router instead: resources `hydra-olympus-1-ssh` and
`hydra-olympus-2-ssh` sit in group `k3s-nodes-ssh`, and policy
`ssh-to-k3s-nodes` grants `svc-ssh` TCP 22 only. `svc-lan` is full Olympus
LAN access for administrators (only `role-admin` carries it), so it includes
node SSH; `svc-ssh` grants node SSH without the rest of the LAN. The primary
mesh has no `Default` All-to-All policy: access exists only through explicit
policies.

## Gotchas

- `dnsZoneRef` matches the NetBird DNS zone by Name. Records are
  `<svc>.<namespace>.<zone name>`.
- The routing peers' NetBird group is operator-generated
  `networkrouter-<network-id>-<hash>`, not `k8s-routers`. `k8s-routers` is the
  NetworkRouter and Network name.
- The operator also runs the legacy NBRoutingPeer, NBResource, NBGroup, and
  NBPolicy controllers unconditionally. Orphaned legacy `nb*` CRs in the
  cluster get reconciled. Remove them first.
- Operator v0.8.0 injects `NB_DISABLE_UPDATE_SETTINGS=true` into routing
  pods. With client 0.73+ the daemon then rejects Login because
  `NB_MANAGEMENT_URL` counts as a config override. The NetworkRouter
  `workloadOverride` sets it back to `false` (upstream removed it on main).
- Pod DNS resolves `*.mia.cx` to the Traefik VIP, but the relay/STUN server
  lives on the Repair VPS. A server block in the `mia.server` key of
  `argocd/k3s/coredns-custom.yaml` forwards `netbird-relay.mia.cx` and
  `netbird-repair.mia.cx` to real DNS so pods reach the relay.
- Add CoreDNS server blocks to the existing `mia.server` key, not a new
  `.server` key. The `reload` plugin picks up edits to the existing key
  without a restart; a new key is only certain to load at CoreDNS startup.
- The spread is `maxSkew: 1` with `DoNotSchedule` and no `minDomains`. Once a
  lost node's Node object is deleted, all four routers schedule on the
  survivor. While the dead node still exists, the survivor keeps only its own
  two, and with two etcd members a down node also stops the API. After a node
  returns or is replaced,
  `kubectl -n netbird-operator rollout restart deploy/networkrouter-k8s-routers`
  restores the 2/2 spread.
