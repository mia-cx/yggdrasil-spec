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
  KEP-3070 static band the dynamic allocator uses only once the upper band
  is full.
- A netbird.io `Group` + `NetworkResource` pointing at that Service via the
  `k8s-routers` NetworkRouter.
- A NetBird policy granting a `svc-*` permission group TCP 443 to the
  resource group, and a NetBird DNS zone per exact hostname answering the
  pinned IP.
- NetworkPolicies on both ends: Traefik admits only the routing pods on the
  service's entrypoint port, and the backend admits only the Traefik pods
  (see `networkpolicy.yaml` here and `argocd/canary/networkpolicy.yaml`).

| Service        | Entrypoint port | ClusterIP   | Resource group     | Permission group   | Hostname                          |
| -------------- | --------------- | ----------- | ------------------ | ------------------ | --------------------------------- |
| canary         | 10001           | 10.43.0.128 | res-canary         | svc-canary         | canary.mia.cx                     |
| open-wearables | 10002           | 10.43.0.129 | res-open-wearables | svc-open-wearables | health.mia.cx                     |
| oddreads       | 10003           | 10.43.0.130 | res-oddreads       | svc-oddreads       | slop.mia.cx                       |
| cliproxyapi    | 10004           | 10.43.0.131 | res-cliproxyapi    | svc-cliproxyapi    | cpa.mia.cx                        |
| cpa-usage      | 10005           | 10.43.0.132 | res-cpa-usage      | svc-cliproxyapi    | cpa-usage.mia.cx                  |
| nextcloud      | 10006           | 10.43.0.133 | res-nextcloud      | svc-nextcloud      | cloud.mia.cx                      |
| pelican        | 10007           | 10.43.0.134 | res-pelican        | svc-pelican        | panel.mia.cx                      |
| immich         | 10008           | 10.43.0.135 | res-immich         | svc-immich         | photos.mia.cx                     |
| tunarr         | 10010           | 10.43.0.137 | res-tunarr         | svc-tunarr         | tunarr.yggdrasil.mia.cx           |
| argocd         | 10009           | 10.43.0.136 | res-argocd         | svc-argocd         | argocd.yggdrasil.mia.cx           |
| jellyfin       | 10011           | 10.43.0.138 | res-jellyfin       | svc-jellyfin       | jellyfin.mia.cx ¹                 |
| seerr          | 10012           | 10.43.0.139 | res-seerr          | svc-seerr          | seerr.mia.cx ¹                    |
| prowlarr       | 10013           | 10.43.0.140 | res-prowlarr       | svc-prowlarr       | prowlarr.yggdrasil.mia.cx         |
| sonarr         | 10014           | 10.43.0.141 | res-sonarr         | svc-sonarr         | sonarr.yggdrasil.mia.cx           |
| radarr         | 10015           | 10.43.0.142 | res-radarr         | svc-radarr         | radarr.yggdrasil.mia.cx           |
| lidarr         | 10016           | 10.43.0.143 | res-lidarr         | svc-lidarr         | lidarr.yggdrasil.mia.cx           |
| readarr        | 10017           | 10.43.0.144 | res-readarr        | svc-readarr        | readarr.yggdrasil.mia.cx          |
| sabnzbd        | 10018           | 10.43.0.145 | res-sabnzbd        | svc-sabnzbd        | sabnzbd.yggdrasil.mia.cx          |
| qbittorrent    | 10019           | 10.43.0.146 | res-qbittorrent    | svc-qbittorrent    | qbittorrent.yggdrasil.mia.cx      |
| hermes         | 10020           | 10.43.0.147 | res-hermes         | svc-hermes         | hermes.mia.cx ¹                   |
| ms365-mcp      | 10021           | 10.43.0.148 | res-ms365-mcp      | svc-hermes         | ms365-mcp.yggdrasil.mia.cx        |
| smtproxy       | 10022           | 10.43.0.149 | res-smtproxy       | svc-hermes         | smtproxy.yggdrasil.mia.cx         |
| wings          | 10023           | 10.43.0.150 | res-wings          | svc-pelican        | hermes-olympus-1.yggdrasil.mia.cx |
| speedtest      | 10024           | 10.43.0.151 | res-speedtest      | svc-speedtest      | speedtest.mia.cx                  |
| vaultwarden    | 10025           | 10.43.0.152 | res-vaultwarden    | svc-vaultwarden    | warden.mia.cx ¹                   |
| defriend       | 10026           | 10.43.0.153 | res-defriend       | svc-defriend       | defriend.mia.cx                   |

¹ Also answers on its `*.yggdrasil.mia.cx` alias (`jellyfin.`, `seerr.`,
`hermes.`, `vaultwarden.`), with a DNS zone per name.

## What stays public

Since 2026-10-22 everything else is mesh-only. The public Traefik keeps:

- Authentik (`id.mia.cx`, `authentik.yggdrasil.mia.cx`) and NetBird
  (`netbird.mia.cx`), which mesh sign-in needs.
- `discord.mia.cx` (discord-mcp) and `tac.caelest.is` (Caelestis), which
  people off the mesh use.
- Vaultwarden (`warden.mia.cx`, `vaultwarden.yggdrasil.mia.cx`), public
  again since 2026-10-23 so password managers sync off the mesh. Mesh
  devices still resolve it to the private route.
- Nextcloud (`cloud.mia.cx`), public again since 2026-10-25. Peers in
  `svc-nextcloud` still resolve it to the private route.
- Hermes' Microsoft Graph webhook (`hermes.mia.cx/msgraph/webhook`), which
  Microsoft's servers call.
- Two `ClientIP`-restricted machine paths: Wings to the panel's remote API
  (`10.0.1.6`), and the panel to Wings (pod IPs `10.42.0.0/16`).

## Adding a service

1. Pick an unused entrypoint port and a free `10.43.0.x` IP (from
   `10.43.0.128/25`); add both to the table above.
2. Add `ports.<service>` in `values.yaml` (`expose.default: false`) and
   make sure the NetworkPolicy's port range in this directory covers it.
3. Write the pinned ClusterIP Service and the `Group` + `NetworkResource`
   in this directory.
4. Deploy the app, its Certificate, and a class-annotated IngressRoute
   (`entryPoints: [<service>]`) in its own namespace; add the namespace to
   `providers.kubernetesCRD.namespaces`. Routes needing Authentik
   forward-auth use the namespace-local `authentik` Middleware from
   `forward-auth.yaml`; add the namespace there. Give the backend an Ingress
   NetworkPolicy that admits only the `traefik-internal` pods (see
   `argocd/canary/networkpolicy.yaml`), so nothing can skip the mesh path.
5. Create the NetBird policy and DNS zone below.

## Live NetBird objects

Created through the Management API on 2026-09-27; not in this repo.

- Policy `canary`: source group `svc-canary`, destination group `res-canary`,
  TCP 443.
- DNS zone `canary.mia.cx`: distribution group `svc-canary`, search domain
  off, apex A record `canary.mia.cx` → `10.43.0.128`.

Added through the Management API on 2026-10-21 after Hecate sign-in created
the JWT-issued `svc-cliproxyapi` group:

- Policies `cliproxyapi` and `cpa-usage`: source `svc-cliproxyapi`, respective
  destinations `res-cliproxyapi` and `res-cpa-usage`, unidirectional TCP 443.
- DNS zones `cpa.mia.cx` and `cpa-usage.mia.cx`: distribution group
  `svc-cliproxyapi`, search domain off, apex A records pointing at
  `10.43.0.131` and `10.43.0.132`, respectively.

Added on 2026-10-21, when Nextcloud and Pelican went mesh-only, in the same
shape: policies `nextcloud` and `pelican` (source `svc-<name>`, destination
`res-<name>`, unidirectional TCP 443), and DNS zones `cloud.mia.cx` →
`10.43.0.133` and `panel.mia.cx` → `10.43.0.134`, distributed to the matching
`svc-<name>` group.

Added on 2026-10-21, when Tunarr went mesh-only for the Node.js security
release, in the same shape: policy `tunarr` and DNS zone
`tunarr.yggdrasil.mia.cx` → `10.43.0.137`. Tdarr's port 10009 and
`10.43.0.136` are free since its removal. Immich's policy `immich` and zone `photos.mia.cx` →
`10.43.0.135` followed in the same shape once sign-in created the JWT-issued
`svc-immich` group.

Added on 2026-10-22, when the rest of the homelab went mesh-only, in the same
shape: one policy per row of the table above (named after the service), and
one DNS zone per hostname, distributed to the row's permission group.

NetBird 0.79.0 doesn't push DNS zone or record changes to connected peers.
The server logs `failed to get network map data ... context canceled`, and
peers keep their old DNS settings until they reconnect
(`netbird down && netbird up`). Group and policy changes push normally, in
under 10 seconds.

## Verified on 2026-09-27

| Check                                              | Result                                                                        |
| -------------------------------------------------- | ----------------------------------------------------------------------------- |
| Peer in `svc-canary` opens `https://canary.mia.cx` | 200, Let's Encrypt certificate verifies                                       |
| Same peer removed from `svc-canary`                | Route and DNS answer gone, connection fails within 10 seconds; back on re-add |
| Pod in `default` to `10.43.0.128:443` or `whoami`  | Blocked by the NetworkPolicies                                                |
| Public Traefik with `Host: canary.mia.cx`          | 404                                                                           |
| IngressClass, TLSStore, TLSOption                  | Unchanged: only the public `traefik` class and `kube-system/default` store    |
| `cmctl renew canary-tls -n canary`                 | New certificate served at once, no restart                                    |
