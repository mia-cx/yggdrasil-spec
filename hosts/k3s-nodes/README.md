# K3s node NetBird clients

## Known issue — do not enroll yet

Enrolling a node currently crash-loops K3s. NetBird writes `-i wt0` accept
rules into the iptables-nft `ip filter` table, which k3s's bundled iptables
cannot parse, so the embedded kube-router netpol controller fatals on
`cmp sreg undef` ([kube-router#1788](https://github.com/cloudnativelabs/kube-router/issues/1788),
[k3s#11493](https://github.com/k3s-io/k3s/issues/11493)). Blocked pending a
fix decision (see #26). The install script refuses to run without a host
`iptables` binary.

Each K3s host runs a persistent OS-level NetBird client for maintenance
access. It works independently of any pods on the host. The node enrolls as
its own peer, separate from the cluster's routing pods.

## Prerequisites

- A NetBird group named `k3s-nodes`.
- A reusable setup key created by an admin: auto-grouped to `k3s-nodes`,
  usage limit equal to the node count, 24 hour expiry, not ephemeral.

## Install

Run from the repo root on your workstation, then on the node:

```bash
scp hosts/k3s-nodes/install-netbird-client.sh <node>:
ssh <node>
install -m 600 /dev/stdin ~/netbird-setup-key   # paste the key, then Ctrl-D
sudo ./install-netbird-client.sh ~/netbird-setup-key
rm ~/netbird-setup-key
```

The script installs the pinned `0.79.0` client and enrolls the node. The
`--disable-dns` flag leaves host DNS resolution untouched. The
`--disable-client-routes` flag keeps node routing independent of mesh routes.

If `sudo` needs a password you do not have, run the script as root on the
host via a debug pod:
`kubectl debug node/<node> --profile=sysadmin --image=busybox:1.36 -- nsenter -t 1 -m -u -i -n -p -- bash /home/mia/install-netbird-client.sh /root/k3s-nodes.setup-key`

Revoke the setup key once every node has enrolled.

## Access

The `ssh-to-k3s-nodes` policy lets `svc-ssh` members reach `k3s-nodes` on
TCP port 22 only. Enrolling a node grants no pod access: no policy connects
`k3s-nodes` to the routing group or to network resources.

## Verify

```bash
netbird status -d
cat /etc/resolv.conf   # unchanged
ip -br link show wt0
```

## Remove

```bash
sudo netbird down
sudo netbird service uninstall
sudo apt-mark unhold netbird
sudo apt-get purge netbird
sudo rm /etc/apt/sources.list.d/netbird.list /usr/share/keyrings/netbird-archive-keyring.gpg
```

Then delete the node's peer in the NetBird dashboard.
