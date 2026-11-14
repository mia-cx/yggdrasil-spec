# Exit nodes

`compose.yaml` runs a primary-mesh exit node on any Docker host, as its own
compose project in `/opt/netbird-exit`. Its `EXIT-PRIVATE` chain drops
forwarded mesh traffic to `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
`100.64.0.0/10`, `169.254.0.0/16`, `fc00::/7` and `fe80::/10`. Users reach the
internet through the exit, but not the host's LAN, the provider's private
network, cloud metadata (`169.254.169.254`) or other peers. Only run exits
from this file: NetBird cannot limit an ordinary device's exit to the public
internet.

| Exit                            | Peer           | Host                                |
| ------------------------------- | -------------- | ----------------------------------- |
| EU West (Netherlands, Arnhem)   | `olympus-exit` | `yggdrasil-olympus-1` (own compose) |
| EU Central (Germany, Nuremberg) | `repair-exit`  | `yggdrasil-repair-1`, this file     |

Every exit is offered to `guest` and `netbird-enroll` with Auto Apply off,
so each person picks one in their client's exit node selector. Clients do not
fall back on their own: while an exit is offline, devices using it lose
internet until the user picks another exit or none.

## NetBird objects

- Group `routers-exit`: every exit peer (setup key auto-group).
- Group `exit`: access control group of every exit route.
- Policy `exit`: `guest` and `netbird-enroll` → `exit` and `routers-exit`,
  all protocols. Management only sends a route to peers that can see its
  routing peer, so the policy names both groups.
- One route per exit, named for its location, with `peer` set to that exit's
  peer (not `peer_groups`: `routers-exit` holds every exit, and a group would
  make the exits backups of one route instead of separate choices).
  `0.0.0.0/0`, distribution `guest` and `netbird-enroll`, access control
  group `exit`, masquerade on, Auto Apply off.

## Add an exit

With an admin PAT (`api=https://netbird.mia.cx/api`,
`auth="Authorization: Token $ADMIN_PAT"`):

1. Mint a one-off setup key, auto-group `routers-exit`, 24h expiry.
2. On the host, as root:

   ```bash
   install -d /opt/netbird-exit
   # copy compose.yaml there, then write .env (0600):
   #   NB_HOSTNAME=<short-name>-exit
   #   NB_SETUP_KEY=<key>
   cd /opt/netbird-exit && docker compose up -d
   docker compose exec netbird-exit netbird status
   sed -i 's/^NB_SETUP_KEY=.*/NB_SETUP_KEY=/' .env   # spent once enrolled
   ```

3. Copy an existing exit route with this peer and the new name:

   ```bash
   peer=$(curl -sf -H "$auth" $api/peers | jq -r '.[] | select(.name=="<short-name>-exit") | .id')
   curl -sf -H "$auth" $api/routes | jq --arg p "$peer" --arg n "<Region (Country, City)>" \
     'first(.[] | select(.network == "0.0.0.0/0"))
      | {network_id: $n, description: "Internet via \($n)", network, peer: $p, groups,
         access_control_groups, metric, masquerade, enabled, keep_route, skip_auto_apply}' |
     curl -sf -H "$auth" -H 'Content-Type: application/json' -d @- $api/routes
   ```

4. From a guest test peer, select the exit and check that
   `wget -qO- http://ifconfig.me/ip` shows the host's IP and that a LAN
   address and `169.254.169.254` time out.
