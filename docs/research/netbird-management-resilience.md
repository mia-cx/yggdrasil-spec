# NetBird management resilience with a home primary

Research date: 2026-09-14. Decision input for [Management resilience with a home primary](https://github.com/mia-cx/yggdrasil-spec/issues/6), under [Private Yggdrasil access with NetBird and Hecate](https://github.com/mia-cx/yggdrasil-spec/issues/5). No deployment decision or infrastructure change accompanies this report.

I recommend a home primary with an independent VPS relay and tested off-site recovery first. A dormant management standby is a possible later addition. Automatic management failover introduces state ownership and identity recovery work that a relay alone avoids.

## What upstream supports

| Deployment | Supported behavior | Implication for Yggdrasil |
| --- | --- | --- |
| Community single server | Management, Signal, Relay and STUN can share one server. SQLite is the default. | Smallest home deployment; bundled restarts also restart the relay. |
| Community split deployment | External relays receive connections directly. Signal and PostgreSQL can also run separately. | A VPS can provide relay/STUN independently of home management. Separation alone does not replicate management. |
| Enterprise active-active | Multiple Management and Signal instances use shared PostgreSQL, Redis and NATS. | Licensed HA requires substantially more infrastructure than one spare VPS. |
| Community active-passive recovery | Backup is documented; the reviewed docs provide no turnkey standby election or failover procedure. | An operator-designed restore-and-promote process needs its own validation. |

The first two rows follow NetBird's [split deployment guide](https://docs.netbird.io/selfhosted/maintenance/scaling/scaling-your-self-hosted-deployment). The [Enterprise HA guide](https://docs.netbird.io/selfhosted/maintenance/scaling/high-availability) explicitly requires a commercial license for active-active Management and Signal. It specifies HA PostgreSQL and Redis endpoints, three NATS nodes across failure domains, and load balancers. Ordinary Signal keeps peer connection state in memory; duplicating its container does not create coordinated signaling.

The [backup guide](https://docs.netbird.io/selfhosted/maintenance/backup) documents configuration copies and stopped-server data-directory copies. Treat this as a recovery building block, not a vendor promise of automatic community HA.

## What survives an outage

Management distributes network state. Signal coordinates peer connection establishment. Relay carries encrypted traffic when direct connectivity fails. These roles fail independently in a split deployment. [NetBird architecture](https://docs.netbird.io/about-netbird/how-netbird-works)

| Failure | Existing traffic | New activity |
| --- | --- | --- |
| Management stops; peers and transport remain healthy | Established direct or independently relayed connections can continue. | Enrollment and policy changes stop. Do not promise reconnects after client restart or network change. |
| Bundled server restarts | Direct traffic can continue; its relay sessions drop and reconnect. | Control services must return before normal operation resumes. |
| Independent VPS relay fails | Direct connections are unaffected; sessions using that relay lose their transport. | Another configured relay may provide recovery, but interruption must be tested. |
| Hecate is unavailable | Application sessions depend on each application's session and token behavior. | Fresh Hecate authentication cannot complete. |
| Home loses power or WAN | A VPS cannot reach media behind the failed home connection. | Management recovery elsewhere does not restore home applications. |

NetBird documents established-session tolerance in its [split deployment guide](https://docs.netbird.io/selfhosted/maintenance/scaling/scaling-your-self-hosted-deployment). Its [commercial-license FAQ](https://docs.netbird.io/selfhosted/enterprise) distinguishes bundled relay restarts from independent relay continuity, and identifies blocked enrollment and policy changes. Clients [contact Management on startup](https://docs.netbird.io/client/connect-on-startup).

The last two rows are dependency conclusions, not tested guarantees for this installation. Also distinguish a new application request over an existing tunnel from establishing a new tunnel. Neither user sessions nor relay credentials should be assumed valid indefinitely.

## Proposed recovery design

Keep one authoritative Management deployment. Store encrypted, restorable backups outside the home failure domain. Optionally prepare a stopped VPS copy with matching versions. This is a proposed manual recovery design, not documented automatic NetBird failover.

Preserve these as one recovery set:

1. **Management state and configuration.** Preserve accounts, peers, addresses, policies, routes, DNS and setup keys. Include every configured store, including activity and embedded-auth stores. Preserve `server.store.encryptionKey`; it encrypts sensitive database values. [Configuration reference](https://docs.netbird.io/selfhosted/maintenance/configuration-files)
2. **Runtime identity and secrets.** Preserve the full data directory and deployed configuration, rather than guessing individual key files. Keep image versions, secret references and proxy configuration with the restore manifest. Upstream documents separate backup layouts for combined and older containers. [Backup guide](https://docs.netbird.io/selfhosted/maintenance/backup)
3. **Relay configuration.** Preserve matching Management/relay authentication secrets, advertised relay URLs and TLS provisioning. External relays require a public address; upstream lists 1 CPU and 1 GB RAM as its baseline. This sizes a relay, not a combined recovery host. [External relay guide](https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays)
4. **Hecate identity.** Back up Authentik PostgreSQL and applicable static volumes. Preserve its OIDC provider/client configuration and signing material. Database-backed configuration and imported certificates belong to Authentik's recovery set. [Authentik backup guide](https://docs.goauthentik.io/sys-mgmt/ops/backup-restore/)
5. **Peer identities.** Persist each routing peer's own state. Management recovery cannot repair a pod that regenerates its identity on every restart. This requirement follows the observed routing-pod behavior in [Management resilience with a home primary](https://github.com/mia-cx/yggdrasil-spec/issues/6).

Preserve Authentik's `AUTHENTIK_SECRET_KEY` too. Changing it invalidates active sessions. Current Authentik stores sessions in PostgreSQL; verify the deployed version before designing recovery. [Authentik configuration](https://docs.goauthentik.io/install-config/configuration/)

A backup restores yesterday's authorization too. Proposed recovery therefore includes reconciling revocations and policy changes since the backup before exposing the restored service. The acceptable backup age is a security and availability decision, not merely a storage setting.

## Endpoint ownership and WAN partitions

Keep `netbird.mia.cx` stable while changing its backend. Preserve Hecate's issuer and registered callbacks at `id.mia.cx`. NetBird's HA guide requires stable URLs and HTTP/2/gRPC-capable frontends; relay frontends need WebSockets. [HA guide](https://docs.netbird.io/selfhosted/maintenance/scaling/high-availability)

Two proposed endpoint choices deserve comparison:

| Choice | Benefit | Cost |
| --- | --- | --- |
| Change public and relevant internal DNS after promotion | Few permanent components | DNS caches and client retry timing delay convergence. Internal overrides must follow the same active backend. |
| Stable external frontend forwarding to the active site | Backend switching does not require client DNS changes | Adds an always-on dependency and a home-backend path that must work without NetBird bootstrap. |

Neither endpoint technique replicates state or proves the old primary stopped. Client reconnection uses backoff, so DNS TTL alone is not a recovery-time promise. [Client retry settings](https://docs.netbird.io/client/environment-variables)

A failed heartbeat cannot distinguish home failure from a broken home-to-VPS path. Promoting a copied database while home still serves clients creates two authorities. PostgreSQL documents fencing the former primary and recreating a standby after promotion. [PostgreSQL failover](https://www.postgresql.org/docs/current/warm-standby-failover.html)

For the proposed community design, require confirmed shutdown or effective fencing before promotion. DNS changes alone are insufficient: cached and internal answers can still reach home. If fencing cannot be established, retain the outage rather than create two writable authorities. Failback is a controlled transfer of the newest authoritative state, not restarting the old copy. These are design constraints inferred from the single-writer requirement.

Synchronous cross-WAN replication would trade write availability and latency for tighter data protection. Asynchronous copies accept a loss window. Two locations cannot independently declare themselves primary during a partition and retain one consistent history. Select that tradeoff before introducing automatic promotion.

## Public bootstrap and Hecate

NetBird documents Authentik through OIDC, including issuer, client secret and strict callback registration. Its current recommended integration uses the embedded IdP as a broker; standalone Authentik is also documented. Preserve the existing integration until its deployed mode is inventoried. [Authentik integration](https://docs.netbird.io/selfhosted/identity-providers/authentik)

Derived requirement: a disconnected user must reach Management and Hecate's required authentication endpoints before joining the mesh. Mesh-only access to those endpoints creates a bootstrap loop. Private media boundaries therefore need explicit bootstrap exceptions. An external frontend must not depend exclusively on the mesh it helps establish.

If Hecate remains solely at home, VPS management recovery does not provide fresh Hecate login during a home outage. Options for Mia are accepting that limit, recovering Hecate too, or designing independent identity availability. A local emergency administrator is another explicit policy choice; it does not provide ordinary Hecate user access.

## First-site recommendation and decisions

First repair the observed management failure and routing-peer persistence. Live discovery found `netbird.mia.cx` returning 502 through the failing `10.0.1.4:8081` upstream. It did not establish the host-level cause. DNS ownership also needs resolution before a reliable endpoint failover plan. [Discovery record](https://github.com/mia-cx/yggdrasil-spec/issues/6)

Then plan one home primary, an optional independent VPS relay/STUN, and off-site backups with an isolated restore rehearsal. Keep automatic failover outside the first slice. This is my proportional recommendation; it accepts control-plane downtime while home media already shares the home failure domain.

Mia must choose:

1. Acceptable management recovery time and backup loss window, including stale permission recovery.
2. VPS scope: relay only, dormant management recovery, or management plus Hecate recovery.
3. Whether fresh Hecate login must survive a complete home outage.
4. Manual fencing and endpoint-switch ownership, or the larger infrastructure budget needed for automatic HA.

An isolated rehearsal should cover restored peer identities and permissions, fresh Hecate login, client restart, network change, and controlled failback. Measure those outcomes before promising recovery times. No live probes, purchases or restore tests were performed for this report.
