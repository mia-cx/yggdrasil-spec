---
title: Private Traefik
---

# Private Traefik

A separate private Traefik is part of the [accepted DNS/ingress decision](https://github.com/mia-cx/yggdrasil-spec/issues/10#issuecomment-5742199940). This page describes its end state, not a completed deployment.

## Target boundary

After their approved cutover, private applications require NetBird even on the home LAN. Public applications remain on public Traefik. In the end state, an application uses both only when approved endpoint exceptions require it.

| Component                    | Public Traefik                                 | Private Traefik target                                  |
| ---------------------------- | ---------------------------------------------- | ------------------------------------------------------- |
| Service exposure             | Existing LoadBalancer VIP                      | ClusterIP only                                          |
| Client path                  | Existing public entrance                       | Explicit NetBird resource through cluster routing peers |
| Routes                       | Public services and approved public exceptions | Private service hostnames                               |
| DNS for disconnected clients | Existing public DNS                            | Public Janus binding, not the private origin            |
| Certificates                 | Existing public ingress certificates           | Namespace-local Secret using Cloudflare DNS-01          |

The private listener has no LAN VIP, NodePort, host-port binding, or public router forward. Separate ingress selection prevents public Traefik from loading private routes. Backend and workload restrictions must also reject direct access.

A shared HTTPS destination does not provide per-service NetBird permissions. The [Jellyfin network cutoff](../../infrastructure/netbird.md#jellyfin-network-cutoff) requires a separately enforceable destination that other permitted listeners cannot bypass. A distinct hostname or resource label alone is insufficient. Keep the existing Jellyfin URL; the endpoint design and active-flow cutoff remain validation gates. Other services use Hecate or native application permissions unless separately isolated. Trusted workload-to-workload traffic gets explicit permissions rather than a blanket LAN exception.

The second process separates routing configuration. It does not remove shared K3s failure modes or isolate compromised workloads by itself.

## Canary isolation

Use the distinct `traefik-internal` CRD ingress class and configure the private provider to select it. Keep existing public routes and provider settings unchanged. Use a compatible class annotation or field without changing shared CRD ownership as an installation side effect.

Reference namespace-local certificate Secrets from private routes. Do not introduce another default TLSStore, TLSOption, or IngressClass: those resources can affect the current controller despite a separate route class. The [canary isolation evidence](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743501773) includes the inspected Traefik version and source behavior.

## Migration boundary

Prove NetBird stability using canaries and obtain Mia's sign-off before any production service requires it. Keep current Traefik and its existing routes unchanged throughout setup and the pilot. Prepare private ingress alongside that path; existing service access remains available while users adopt Hecate/native authentication and NetBird.

Each service moves only after its readiness checks and Mia's approval. Coordinate that service's private DNS, public Janus binding, public-origin removal, and backend restrictions. This temporary coexistence is preparation, not a permanent public bypass. Services not yet migrated retain their existing routes.

## Remaining implementation decisions

The [accepted K3s integration](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743564646) selects the operator routing pool, node clients, workload boundaries, and DNS contract. [Choose migration order and acceptance checks](https://github.com/mia-cx/yggdrasil-spec/issues/14) selects pilot criteria, per-service sequencing, and rollback. Concrete version pins, manifests, and validation require separate implementation authorization.

## Related documentation

- [DNS](../../infrastructure/dns.md)
- [Traefik](../../infrastructure/traefik.md)
