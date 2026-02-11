---
title: Naming Scheme
---

# Naming Scheme (Mythology Theme)

## Hierarchy

```
Yggdrasil (world tree - entire infrastructure)
├── Olympus (your home - primary site)
│   ├── Athena (workstation host/VM)
│   ├── Hydra (K3s cluster)
│   └── ...
├── Elysium (mom's site - future)
├── Arcadia (dad's site - future)
└── Hera (WiFi SSIDs - spans all sites)
```

## Current Names

Categories: **abstract** (network / overall infra) → **site** → **hardware** → **vm** → **service**. Table is sorted by category.

| Category | Entity                 | Name            | Mythology | Reason                                                               |
| -------- | ---------------------- | --------------- | --------- | -------------------------------------------------------------------- |
| abstract | Overall infrastructure | **Yggdrasil**   | Norse     | World tree connecting all realms                                     |
| abstract | WiFi SSIDs             | **Hera**        | Greek     | Marriage - "marries" devices                                         |
| abstract | K3s cluster            | **Hydra**       | Greek     | Multi-headed, regenerates                                            |
| site     | Your home site         | **Olympus**     | Greek     | Primary location, seat of power                                      |
| hardware | Workstation            | **Athena**      | Greek     | Wisdom, crafts                                                       |
| hardware | Old server             | **Antheia**     | Greek     | Legacy hardware (Charis/garden)                                      |
| hardware | Mini-PC (Proxmox node) | **Echo**        | Greek     | Many similar instances (see below)                                   |
| vm       | Gateway worker         | **Janus**       | Roman     | God of doorways, thresholds                                          |
| vm       | NFS / Storage LXC      | **Mnemosyne**   | Greek     | Memory (storage)                                                     |
| service  | Authentik              | **Hecate**      | Greek     | Crossroads, boundaries (identity)                                    |
| service  | Nextcloud              | **Clio**        | Greek     | Muse of history, records                                             |
| service  | Jellyfin               | **Thalia**      | Greek     | Muse of comedy, festivity (media)                                    |
| service  | Immich                 | Iris            | Greek     | Goddess of the rainbow and light; Fits “images,” color, and sharing. |
| service  | Vaultwarden            | Cardea          | Roman     | Goddess of hinges and doorways. Fits access control.                 |
| service  | Pelican (game servers) | Hermes          | Greek     | Speed, games, athletes, cunning. Often linked to contests and play.  |
| service  | Netbird (overlay)      | **Yggdrasil**   | Norse     | Same as overall project — overlay connecting everything              |
| service  | Forgejo                | **Hephaestus**? | Greek     | Git hosting (planned) — forge/craft                                  |
| service  | Matrix                 | TBD             | —         | Chat (planned)                                                       |
| service  | Home Assistant         | TBD             | —         | Home automation (planned)                                            |
| service  | Federated social       | TBD             | —         | Mastodon or Misskey+Cherrypick (planned)                             |

**Note:** Backend / non–consumer-facing services (Radarr, Sonarr, Tdarr, Prowlarr, download clients, FlareSolverr, Privoxy, Tunarr, etc.) do not need deity names.

**Optional services to host:** See [Services roadmap](../roadmaps/services/self-hosted.md) for candidate services (wiki, music, finance, analytics, bookmarks, etc.) with short descriptions and why to host them. Add a row and deity name in this table when you deploy one.

## Domain

`yggdrasil.mia.cx`

All services use subdomains: `*.yggdrasil.mia.cx`

## Mini-PC role name: “many identities”

Mini-PCs are similar hardware serving the same role (Proxmox node + one K3s VM each). A deity or figure associated with **many similar instances** fits well. Options considered:

| Name        | Mythology | Why it fits                                                                            | Note                                  |
| ----------- | --------- | -------------------------------------------------------------------------------------- | ------------------------------------- |
| **Echo**    | Greek     | Nymph who repeats; many “copies” of the same. Fits “many similar instances, one role.” | **Chosen.** Short, memorable.         |
| **Proteus** | Greek     | Sea god who could assume any form; “protean” = many forms.                             | Strong alternative.                   |
| **Loki**    | Norse     | Shapeshifter, many identities/variants. Fits Yggdrasil theme.                          | Trickster connotation.                |
| **Spartoi** | Greek     | Warriors from dragon’s teeth; many similar fighters.                                   | Obscure; plural awkward in hostnames. |

We use **Echo**: hostnames `echo-<site>-X` (metal) and `hydra-<site>-echo-X` (K3s VM).

## Service names (applications and LXCs)

Applications and LXCs use deity names; when they need a hostname (e.g. an LXC), they are scoped to the Proxmox host and site for easier debugging.

| Service   | Deity name    | Hostname pattern (if applicable)  | Note                                                                                   |
| --------- | ------------- | --------------------------------- | -------------------------------------------------------------------------------------- |
| NFS LXC   | **Mnemosyne** | `mnemosyne-<proxmox-host>-<site>` | Not numbered; one per Proxmox host that runs NFS. Example: `mnemosyne-athena-olympus`. |
| Authentik | **Hecate**    | (runs in K3s)                     | Identity / SSO.                                                                        |
| Nextcloud | **Clio**      | (runs in K3s)                     | Records, files.                                                                        |
| Jellyfin  | **Thalia**    | (runs in K3s)                     | Media.                                                                                 |
| Netbird   | **Yggdrasil** | (management + agents)             | Same name as the overall project — the overlay that connects everything.               |

## Hostnames: include site for every host

For easier debugging and clarity in multi-site setups, **every hostname includes the site name**.

| Host type                              | Pattern                           | Example                        |
| -------------------------------------- | --------------------------------- | ------------------------------ |
| Named host (e.g. workstation, gateway) | `<name>-<site>`                   | athena-olympus, janus-olympus  |
| LXC scoped to Proxmox host             | `<service>-<proxmox-host>-<site>` | mnemosyne-athena-olympus       |
| Mini-PC (Proxmox node)                 | `echo-<site>-X`                   | echo-olympus-1, echo-elysium-1 |
| K3s VM on that mini-PC                 | `hydra-<site>-echo-X`             | hydra-olympus-echo-1           |

So at Olympus you see athena-olympus (workstation), echo-olympus-1 (first mini-PC), hydra-olympus-echo-1 (its K3s VM); at Elysium, echo-elysium-1, hydra-elysium-echo-1, etc. The number **X** is derived from IaC (e.g. OpenTofu list or count); adding a new mini-PC = add one entry. See [Node onboarding roadmap](../roadmaps/infrastructure/node-onboarding.md).

## Naming Philosophy

- **Norse** for overarching concepts (Yggdrasil connects all realms)
- **Greek** for specific devices and services at Olympus
- **Roman** exceptions where no Greek equivalent exists (Janus)
- Future sites may use other mythologies (Egyptian, Celtic, etc.)
