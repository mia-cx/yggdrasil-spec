# K3s mesh DNS and routing feasibility

Research date: 2026-09-14. Planning evidence for [K3s mesh DNS and routing feasibility](https://github.com/mia-cx/yggdrasil-spec/issues/11), within [Private Yggdrasil access with NetBird and Hecate](https://github.com/mia-cx/yggdrasil-spec/issues/5).

## Recommendation

Use persistent NetBird clients installed on the K3s node operating systems. Give nodes mesh DNS independently of Kubernetes. Keep ordinary pods on Kubernetes DNS, with explicit forwarding for the mesh namespace. Permit pod-to-mesh traffic through narrowly scoped node forwarding and source NAT rules, with Kubernetes policy controlling which workloads can use them.

This is a proposed integration of documented components, not an upstream-tested K3s recipe. Prove it on one node and one test workload before adopting it. Keep the existing CNI and Kubernetes node addresses during this first-site integration. A mesh connection does not require moving the cluster's control plane or pod transport onto it.

Use the NetBird operator when declarative service exposure or selected workload egress earns its additional controller. It is useful, but does not replace node-level recovery access. Home management remains outside K3s. Its public endpoint, Hecate login, and bootstrap DNS must remain reachable without cluster DNS or an established mesh connection.

## Evidence and current constraints

Earlier read-only discovery found two Ready K3s servers, `10.0.1.3` and `10.0.1.10`. The existing routing DaemonSet uses `hostNetwork: true`, `ClusterFirstWithHostNet`, and NetBird `0.78.1`. It mounts `/dev/net/tun` but no persistent client state. Startup logs generate new WireGuard identities. Both pods repeatedly fail management requests with HTTP 502 through upstream `10.0.1.4:8081`.

The live inventory also contains two Services claiming `10.0.128.3`: `dns/coredns-internal` and `kube-system/coredns-lb`. Queries to that address returned the ingress VIP for both private names and unrelated public names. **Those replies do not identify which DNS backend answered.** The versioned `argocd/k3s/coredns-custom.yaml` independently proves that one configured DNS view synthesizes A records for the entire `mia.cx` zone. Resolve address ownership and inspect each backend before changing DNS.

These observations are inputs, not new live tests. This research performed no cluster mutations or network probes.

## Node agents, routing pods, and workload identities

NetBird stores Linux client state, configuration, and WireGuard keys under `/var/lib/netbird`, unless `NB_STATE_DIR` overrides it. Its Docker examples mount that directory persistently. Infrastructure nodes should retain their identity across daemon restarts and OS maintenance. Use one writable state directory per peer, never a shared identity copied across nodes. [Client state configuration](https://docs.netbird.io/client/environment-variables), [Docker installation](https://docs.netbird.io/get-started/install/docker).

The current DaemonSet's missing state volume is therefore a reliability problem for a design expecting stable node identities. A host-network DaemonSet also starts only after Kubernetes can schedule it. Installing the node client as an OS service removes that scheduling dependency. This is a design inference, not a guarantee that established tunnels survive every management or host failure.

The operator offers distinct models. `NetworkRouter` exposes resources through routing pods; `NetworkResource` maps a Kubernetes Service's ClusterIP into NetBird. `SidecarProfile` makes a matching pod its own peer, useful where a workload needs independent permissions. Sidecar enrollment and lifecycle increase per-workload complexity. [Operator overview](https://docs.netbird.io/use-cases/kubernetes), [Client sidecar](https://docs.netbird.io/use-cases/kubernetes/client-sidecar).

Operator `v0.8.0` creates routing peers with ephemeral setup keys and an `emptyDir` at `/var/lib/netbird`. State survives a container restart inside the same pod, but not pod replacement. That is intentional ephemeral routing capacity. Do not mistake it for durable infrastructure identity. Spread replicas across hosts and attach policy to their managed group. The release adds `NetworkEgress`; verify the selected controller, CRDs, server, and client versions together. [Release](https://github.com/netbirdio/kubernetes-operator/releases/tag/v0.8.0), [Pinned routing controller](https://github.com/netbirdio/kubernetes-operator/blob/41d995671f55d790a4f4e1c37da8c9e41a36abee/internal/controller/networkrouter_controller.go).

## DNS that nodes and pods can both use

Kubernetes `ClusterFirst` pods query cluster DNS. Host-network pods require `ClusterFirstWithHostNet` to retain that behavior. Neither setting means that ordinary pods automatically inherit a node client's mesh resolver. Kubernetes also supports explicit `dnsConfig` with `dnsPolicy: None`. [Pod DNS policies](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/).

Proposed DNS ownership:

| Query | Resolver path |
| --- | --- |
| Kubernetes Service names | Existing CoreDNS Kubernetes plugin |
| Actual NetBird peer namespace | CoreDNS forwards to restricted node DNS bridges, then the local NetBird resolver |
| Selected private `mia.cx` service names | Explicit private records or exact-name forwarding |
| Other public names, including unrelated `mia.cx` services | Independent public upstreams |
| Management and Hecate bootstrap names | Reachable public or explicit local answers independent of K3s |

NetBird documents a site-facing DNS forwarder that sends its mesh namespace to the local NetBird resolver. Apply that pattern to restricted node listeners rather than exposing recursive DNS to the entire LAN. Use the account's actual mesh suffix and discovered resolver address. Do not assume `netbird.cloud` or a fixed `100.x` address. The CLI supports an explicit resolver bind address, which can remove discovery ambiguity. [Site-to-VPN DNS](https://docs.netbird.io/use-cases/remote-access/site-to-vpn#resolving-netbird-dns-names), [CLI resolver option](https://docs.netbird.io/get-started/cli).

CoreDNS supports forwarding particular zones to selected upstreams. Give its default public forwarding path explicit independent upstreams, or a dedicated resolver file that NetBird does not rewrite. Otherwise, node DNS can forward to CoreDNS while CoreDNS forwards back into node DNS. CoreDNS's `loop` plugin catches only certain startup HINFO loops, not every runtime or domain-specific cycle. [CoreDNS forward](https://coredns.io/plugins/forward/), [CoreDNS loop limits](https://coredns.io/plugins/loop/).

NetBird's domain-resource forwarder is a different component from its local peer DNS resolver. It resolves resource names through the routing peer's DNS, on a version-dependent forwarding port. Do not point a routing peer's upstream back at the same domain-resource path. [NetBird DNS components](https://docs.netbird.io/manage/dns).

Removing the broad `mia.cx` override is required to preserve public services. Off-mesh service names should reach the public Cloudflare connection page. Nodes and pods may have an explicit machine DNS view, while humans require NetBird even at home. DNS answers alone cannot enforce that boundary.

## Connectivity and policy

Node processes using their own NetBird client have the node's mesh identity. Ordinary pod packets retain pod source addresses until translated. NetBird's documented Site-to-VPN path requires outbound SNAT to the routing peer's mesh address; the dashboard's masquerade setting controls the opposite direction. The target's policy then authorizes the routing peer identity. [Site-to-VPN forwarding requirements](https://docs.netbird.io/use-cases/remote-access/site-to-vpn).

For the proposed node gateway path, restrict forwarding to the cluster's actual pod ranges and approved mesh destinations and ports. Verify whether existing Flannel rules already translate this path before adding rules. Confirm the final source at the destination. Several permitted workloads sharing a node then share its mesh identity. Kubernetes egress policy must distinguish them before translation. Use a dedicated sidecar or gateway identity when that shared identity grants too much.

Alternatively, `NetworkEgress` exposes one exact external FQDN or IP and declared ports through a normal Kubernetes Service. Pods can use that Service without a general route to the overlay. It does not transparently make every arbitrary mesh hostname usable. Applications using HTTPS must still send the intended TLS server name and HTTP host. The `v0.8.0` API exposes no transport-protocol selector; do not assume it solves arbitrary UDP egress. [NetworkEgress behavior](https://docs.netbird.io/use-cases/kubernetes/routing-peer#networkegress), [Pinned API types](https://github.com/netbirdio/kubernetes-operator/blob/41d995671f55d790a4f4e1c37da8c9e41a36abee/api/v1alpha1/networkegress_types.go).

For mesh-to-private-service traffic, keep masquerade initially. It avoids requiring the ISP router to learn return routes. Disabling it requires explicit destination return routing and a failover strategy for that return path. Source visibility and uninterrupted failover are separate concerns. Current NetBird guides contain conflicting historical tables about Networks masquerade support; confirm the pinned server/client behavior before selecting a no-SNAT design. [Masquerade](https://docs.netbird.io/manage/networks/masquerade), [Routing behavior](https://docs.netbird.io/manage/networks/how-routing-peers-work).

K3s includes kube-router's NetworkPolicy controller, but confirm it is enabled. Kubernetes does not define uniform NetworkPolicy treatment for host-network pods; many implementations treat their traffic as node traffic. Policies also cannot provide HTTP hostname authorization. [K3s NetworkPolicy](https://docs.k3s.io/networking/networking-services#network-policy-controller), [Kubernetes policy limits](https://kubernetes.io/docs/concepts/services-networking/network-policies/).

Consequently, private ingress must reject non-mesh human paths independently of DNS. Audit LAN VIPs, node ports, host ports, public ingress routes, and IPv6 listeners. A router firewall alone cannot protect traffic exchanged directly on the same LAN. Several services behind one destination IP and TCP port also need service-level authorization. Hecate application policy or native service authorization must distinguish those requests. Keep machine identities and human permissions separate.

## First-site acceptance gates

1. Resolve DNS VIP ownership. Verify private names, an absent private name, `mia.cx`, and `i.mia.cx` from each DNS backend independently. Test A, AAAA, UDP, and TCP DNS.
2. Enroll one persistent node client. Verify mesh resolution and permitted connectivity before K3s starts, after client restart, and during a cluster DNS outage. Check identity retention.
3. Test one ordinary pod on each node. Verify mesh-name resolution, permitted and denied destinations, return traffic, and observed source translation. Confirm unrelated pod egress remains blocked where intended.
4. Test direct LAN and off-mesh paths to every private ingress alternative. Only the public connection page should remain available off-mesh; authorized native Jellyfin playback must still work.
5. Test DNS bridge and routing-peer failure, then recovery. Measure reconnect behavior and DNS caching. Preserve a rollback to the prior explicit DNS configuration and console access throughout.

These are proposed acceptance tests for a later authorized implementation. They have not run.

## Future multi-site constraints

Reserve distinct site LAN, pod, Service, VIP, and overlay ranges. Existing plans allocate `10.0.0.0/16`, `10.1.0.0/16`, and `10.2.0.0/16` to sites; Kubernetes ranges need separate accounting. Selecting between overlapping routes does not make both identical destinations uniquely reachable. Do not route all `100.64.0.0/10` when only the account's assigned block is needed. [Overlapping routes](https://docs.netbird.io/manage/network-routes/overlapping-routes), [Site-to-site prerequisites](https://docs.netbird.io/use-cases/remote-access/site-to-site).

NetBird's CLI defaults its WireGuard MTU to 1280. Encapsulating a CNI tunnel inside it adds overhead, so test packet sizes and long transfers over both direct and relayed paths. Do not assume today's pod MTU remains valid. K3s Flannel defaults to VXLAN; its WireGuard backend is a separate choice. [NetBird MTU](https://docs.netbird.io/get-started/cli), [Flannel options](https://docs.k3s.io/networking/basic-network-options).

K3s documents multicloud deployment, but warns about latency and says embedded-etcd servers should remain together. Its documented VPN integration names Tailscale, not NetBird. This research therefore does not establish support for a stretched NetBird-backed K3s control plane. Prefer independent site clusters as the comparison baseline. Consider remote workers only after measuring WAN loss, latency, DNS isolation, storage behavior, and recovery. [K3s multicloud limits](https://docs.k3s.io/networking/distributed-multicloud).

Before any stretch experiment, validate the chosen API and CNI paths, port ownership, and tunnel MTU. K3s uses UDP 8472 for VXLAN or 51820 for IPv4 WireGuard; NetBird also defaults to 51820. Verify bind compatibility rather than assigning both blindly. Keep cluster transport restricted to infrastructure peers. A VPS relay may improve connectivity, but does not establish management HA, quorum safety, or cross-site storage availability. [K3s network requirements](https://docs.k3s.io/installation/requirements#networking), [NetBird port configuration](https://docs.netbird.io/get-started/cli).
