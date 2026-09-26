---
title: Multi-site resilience
---

# Multi-site resilience

Discussion notes for future planning. Cross-site K3s topology, storage, and multi-cluster tooling remain undecided. This is not a deployment plan.

The current [NetBird Wayfinder map](https://github.com/mia-cx/yggdrasil-spec/issues/5) covers the first-site architecture and staged migration. These notes preserve the options discussed alongside it.

## Cluster boundaries

The existing [network plan](../../architecture/network.md) keeps each site's Proxmox cluster separate. NetBird connects the sites without joining their Proxmox quorum. Proxmox Datacenter Manager can provide [one management interface](https://pdm.proxmox.com/docs/introduction.html) over independent clusters.

Separate K3s clusters per site are the current recommendation, not an accepted decision. Applications can span those clusters through deployment management, service networking, and data replication. A disconnected site retains its own Kubernetes control plane.

A single K3s cluster with remote workers is another option. Existing remote workloads may continue during a disconnection, but scheduling and reconciliation depend on the control-plane site. The [K3s distributed-cluster guide](https://docs.k3s.io/networking/distributed-multicloud) allows distributed agents while advising that server nodes remain in the same location. NetBird addresses do not remove WAN latency or quorum requirements.

The earlier [resilience-nodes proposal](./resilience-nodes.md) explores a stretched cluster. Its quorum and overlay-VIP assumptions still need validation; it does not establish a selected cross-site architecture.

## VM high availability within a site

Proxmox HA can restart the primary NetBird VM on another eligible host after a host failure. This runs one VM at a time, not two active NetBird Management instances.

The prerequisites are reliable quorum, fencing, compatible hosts, available VM disks, and matching network bridges/VLANs. Three suitable physical hosts are the usual quorum baseline. [Strict node-affinity rules](https://pve.proxmox.com/pve-docs/chapter-ha-manager.html) can further restrict eligible hosts. Separate per-site clusters keep this HA boundary local.

The VM can retain its LAN address, virtual NIC identity, and persistent NetBird state after restarting elsewhere. Its DNS and router port forwards can therefore remain unchanged. A separate shared VIP is not required for that design. Failover still includes an interruption and VM restart.

HA does not automatically replicate disks. The storage options include:

- Resilient shared storage that remains accessible after the host failure and does not depend on K3s.
- [Proxmox local-ZFS replication](https://pve.proxmox.com/pve-docs/chapter-pvesr.html), which asynchronously copies VM disks to eligible hosts. Writes since the last successful replication can be lost, including recent NetBird enrollment or permission changes. This does not apply automatically to arbitrary local storage.

Choose the storage and acceptable data-loss window when the additional hosts are known. Site-local VM HA is a possible later upgrade, not a prerequisite for the first-site NetBird migration. The independent Repair mesh remains useful for failures that local HA cannot cover.

## Applications across Kubernetes clusters

A Deployment belongs to one cluster. Multi-cluster tooling coordinates separate deployments rather than turning them into one shared Kubernetes object.

### Deployment and placement

The repository already uses ArgoCD. An [ApplicationSet cluster generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/) can deploy one chart or manifest definition to selected clusters with site-specific overrides.

```text
Git application definition
          |
       ArgoCD
       /    \
Olympus    Elysium
Deployment Deployment
Service    Service
```

Each cluster maintains its own workloads. ArgoCD alone does not reallocate replicas between sites after a failure. [Karmada](https://karmada.io/docs/userguide/scheduling/propagation-policy) is an optional controller for cross-cluster placement and configured failover. It does not supply application-data replication. Give each resource a clear controller owner rather than letting competing controllers manage the same object.

### Service connectivity

For selected remote services, explicit DNS names and NetBird routes can be enough. The [NetBird Kubernetes operator](https://docs.netbird.io/use-cases/kubernetes/routing-peer) provides NetworkResource for exposing a service and NetworkEgress for representing a remote destination through a local Kubernetes Service. Pod routing and DNS still need explicit configuration.

[Cilium ClusterMesh](https://docs.cilium.io/en/stable/network/clustermesh/global-services/) is another option. Global Services share backends between identically named Services in participating clusters. This requires Cilium and ClusterMesh setup, not just NetBird connectivity. Its documented default retains stale remote service information when a cluster becomes unreachable; configure and test the failure policy before relying on it for failover.

### User traffic

A health-aware load balancer or DNS failover can keep one service hostname while selecting a site's ingress. A sole global traffic router hosted at the failed site would defeat that design. Ordinary multiple DNS records do not establish health-aware failover.

Public and mesh-only services need suitable entrances of their own. Internal cross-cluster service discovery does not automatically provide a resilient public or private entrance. Avoid requiring a new deployment or GitOps sync during an outage when a pre-deployed standby can serve the workload.

## Data replication across sites

Choose replication per application. A stateless API can often run concurrently at multiple sites. A stateful service needs data availability, a safe writer-ownership model, and a tested promotion procedure. Deploying a second copy of Jellyfin, for example, does not replicate its metadata or media.

Synchronous replication waits for the required remote acknowledgements before completing writes. WAN latency and partitions affect that path. Asynchronous replication copies changes afterward; failover can lose changes that have not arrived. Agree acceptable downtime (RTO) and acceptable data loss (RPO) before choosing the mechanism.

Ceph is independent of Proxmox and can serve Kubernetes or other clients. Installing it at another software layer does not remove its network requirements. [Ceph stretch clusters](https://docs.ceph.com/en/squid/rados/operations/stretch-mode/) have explicit placement, quorum, and partition-handling requirements, including a two-data-site design with a third-site tiebreaker. That is not the default recommendation for unmeasured residential WAN links.

Separate Ceph clusters can instead use [asynchronous RBD mirroring](https://docs.ceph.com/en/squid/rbd/rbd-mirroring/) for selected block images. Mirroring still needs promotion and split-brain handling; it does not make one disk safely writable from both sites. Database-native replication or file/object replication may be a better fit for other applications. File synchronization is not a substitute for safe replication of a running database.

Replication is not a backup strategy on its own. Keep independent recovery points for corruption, deletion, or compromised credentials.

## Decisions for a future effort

- Whether each site needs independent operation during a WAN outage, and which K3s topology meets that requirement.
- Which services need cross-site recovery, and their RTO/RPO targets.
- Available hosts, storage capacity, WAN latency, bandwidth, and packet loss.
- Traffic routing, writer fencing, failover, failback, and restore tests for each selected service.

ArgoCD ApplicationSets, Cilium ClusterMesh, Karmada, Ceph mirroring, and Proxmox VM HA are options described here, not a chosen stack. Continue the first-site NetBird decisions before turning this guidance into a multi-site deployment plan.
