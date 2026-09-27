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
to `svc.olympus.yggdrasil.mia.cx`. The zone's distribution group is
`k3s-nodes` as a required placeholder: the API rejects an empty list, and the
node clients run `--disable-dns` so they ignore it anyway. The DNS work
switches it to `netbird-enroll`.

The sidecar-injection pod webhook only matches namespaces labelled
`netbird.io/sidecar-injection=enabled`.

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
  lives on the Repair VPS. The NetworkRouter sets a `hostAliases` entry for
  `netbird-relay.mia.cx` so the relay check can pass.
