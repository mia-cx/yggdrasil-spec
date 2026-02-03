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

| Entity | Name | Mythology | Reason |
|--------|------|-----------|--------|
| Overall infrastructure | **Yggdrasil** | Norse | World tree connecting all realms |
| Your home site | **Olympus** | Greek | Primary location, seat of power |
| WiFi SSIDs | **Hera** | Greek | Marriage - "marries" devices |
| Home LAN | **Hestia** | Greek | Hearth, home |
| K3s cluster | **Hydra** | Greek | Multi-headed, regenerates |
| Workstation | **Athena** | Greek | Wisdom, crafts |
| Gateway worker | **Janus** | Roman | God of doorways, thresholds |
| Storage LXC | TBD | Greek | Mnemosyne? (memory) |
| Old server | TBD | Greek | Hephaestus? (forge) |

## Domain

`yggdrasil.mia.cx`

All services use subdomains: `*.yggdrasil.mia.cx`

## Naming Philosophy

- **Norse** for overarching concepts (Yggdrasil connects all realms)
- **Greek** for specific devices and services at Olympus
- **Roman** exceptions where no Greek equivalent exists (Janus)
- Future sites may use other mythologies (Egyptian, Celtic, etc.)
