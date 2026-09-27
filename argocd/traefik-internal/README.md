# Private Traefik

A second Traefik instance for services reachable only over the NetBird mesh.
The canary service (`canary.mia.cx`, a `traefik/whoami` pod) is its first
destination. Nothing here is reachable through the public Traefik or the LAN.

## Isolation contract

- The private instance processes only IngressRoutes annotated
  `kubernetes.io/ingress.class: traefik-internal`. The public instance's
  provider class is unset, so it ignores those routes.
- It creates no IngressClass, TLSStore, TLSOption, or CRDs; the public
  `traefik` app owns those.
- It watches an explicit namespace list in `values.yaml`, not the whole
  cluster. New namespaces opt in deliberately.
- Certificates are namespace-local cert-manager Secrets (`canary-tls`),
  issued by the shared `letsencrypt-cloudflare` DNS-01 ClusterIssuer.

## Per-service shape

Each private service gets its own enforceable network destination:

- A dedicated Traefik entrypoint port (kube-proxy maps ClusterIP:443 to the
  pod targetPort, so two services sharing one Traefik port are
  indistinguishable to NetBird L3/L4 policy).
- A pinned ClusterIP from the reserved `10.43.0.128/25` block, inside the
  KEP-3070 static band the dynamic allocator never uses.
- A netbird.io `Group` + `NetworkResource` pointing at that Service via the
  `k8s-routers` NetworkRouter.
- A NetBird policy granting a `svc-*` permission group TCP 443 to the
  resource group, and a NetBird DNS zone per exact hostname answering the
  pinned IP.
- NetworkPolicies on both ends: Traefik admits only the routing pods on the
  service's entrypoint port, and the backend admits only the Traefik pods
  (see `networkpolicy.yaml` here and `argocd/canary/networkpolicy.yaml`).

| Service | Entrypoint port | ClusterIP   | Resource group | Permission group | Hostname      |
| ------- | --------------- | ----------- | -------------- | ---------------- | ------------- |
| canary  | 10001           | 10.43.0.128 | res-canary     | svc-canary       | canary.mia.cx |

## Adding a service

1. Pick an unused entrypoint port and a free `10.43.0.x` IP (from
   `10.43.0.128/25`); add both to the table above.
2. Add `ports.<service>` in `values.yaml` (`expose.default: false`) and add
   the port to the NetworkPolicy in this directory.
3. Write the pinned ClusterIP Service and the `Group` + `NetworkResource`
   in this directory.
4. Deploy the app, its Certificate, and a class-annotated IngressRoute
   (`entryPoints: [<service>]`) in its own namespace; add the namespace to
   `providers.kubernetesCRD.namespaces`. Give the backend an Ingress
   NetworkPolicy that admits only the `traefik-internal` pods (see
   `argocd/canary/networkpolicy.yaml`), so nothing can skip the mesh path.
5. Create the NetBird policy and DNS zone below.

## Live NetBird objects

Created through the Management API after rollout; not in this repo.

- Policy `canary`: source group `svc-canary`, destination group `res-canary`,
  TCP 443.
- DNS zone `canary.mia.cx`: distribution group `svc-canary`, apex A record →
  `10.43.0.128`.
