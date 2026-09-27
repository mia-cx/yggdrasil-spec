# Repair mesh host clients

One unprivileged NetBird client per host, joined to the Repair mesh
(`netbird-repair.mia.cx`, hosted on `yggdrasil-repair-1`). It runs in
userspace netstack mode as the `netbird-repair` system user: no kernel
interface, no nftables rules, no host DNS changes. With local forwarding on,
a connection to the host's own Repair address lands on host loopback, so
allowed TCP 22 reaches the existing `sshd` on `127.0.0.1:22`. That is the
recovery path when the primary mesh, K3s, or home networking is broken.

Per the [accepted dual-mesh design](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743020199)
the Repair client is an independent systemd service with its own state,
socket, logs, and UDP port (`51821`; the primary client's `wt0` owns
`51820`). It depends on `network-online.target` only — not Docker, K3s, or
the primary client.

## Hosts

| Host                 | LAN IP   | SSH for install                            |
| -------------------- | -------- | ------------------------------------------ |
| hephaestus (VM 3002) | 10.0.3.2 | `root@10.0.3.2`                            |
| antheia (Proxmox)    | 10.0.1.8 | `root@10.0.1.8`                            |
| athena (Proxmox)     | 10.0.1.1 | `root@10.0.1.1`                            |
| yggdrasil-olympus-1  | 10.0.1.4 | `ssh -J root@10.0.1.1 mia@10.0.1.4` (sudo) |
| hydra-olympus-1      | 10.0.1.3 | `qm guest exec 1003` on athena             |

## Install

`install.sh` takes the NetBird hostname as its argument and reads the setup
key from stdin — the key never appears in argv or a repo file. It creates
the `netbird-repair` user, installs the checksum-verified `netbird` 0.79.0
binary at `/usr/local/lib/netbird-repair/netbird`, installs and enables the
unit, enrolls, then deletes the key file. Re-running it is safe.

```bash
scp -r hosts/repair-clients root@HOST:/tmp/repair-clients
cat KEYFILE | ssh root@HOST 'bash /tmp/repair-clients/install.sh HOSTNAME'
```

For hydra-olympus-1 (no root SSH), upload the files once via
`qm guest exec 1003` on athena and run the script the same way, piping the
key through `ssh` stdin to `qm guest exec --pass-stdin 1`.

## Verify

From an operator device on the Repair mesh:

```bash
ssh -o HostKeyAlias=10.0.3.2 root@<repair-ip> hostname   # native host key
curl -sk -o /dev/null -w '%{http_code}' https://<repair-ip>:8006/  # Proxmox
```

On the host: `systemctl status netbird-repair`,
`journalctl -u netbird-repair`, and `ss -ulpn | grep 51821`. Before/after
install, `nft list ruleset | grep -ic netbird`, `iptables-save | grep -ic
netbird`, `ip -br link`, and `cat /etc/resolv.conf` must be unchanged except
for the UDP 51821 listener.

## Rotate or re-enroll

Create a fresh setup key on the Repair mesh and re-run `install.sh` the same
way; the script rewrites the key file and re-enrolls. Delete the old peer in
the dashboard.

## Remove

```bash
systemctl disable --now netbird-repair
rm -f /etc/systemd/system/netbird-repair.service /usr/local/lib/netbird-repair/netbird
rm -rf /var/lib/netbird-repair /var/log/netbird-repair /run/netbird-repair
systemctl daemon-reload
userdel netbird-repair   # optionally keep the user
```

Delete the peer on the Repair mesh afterwards.
