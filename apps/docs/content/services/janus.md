---
title: Janus
---

# Janus

## Overview

| Property | Value                  |
| -------- | ---------------------- |
| Type     | Cloudflare Worker      |
| Route    | `*.yggdrasil.mia.cx/*` |
| Runtime  | Cloudflare edge        |

Cloudflare Worker providing friendly landing pages for users not connected to the Yggdrasil overlay network. Named after the Roman god of doorways, gates, and transitions -- Janus has two faces, one looking at those inside the network, one looking at those outside.

When a user tries to access `jellyfin.yggdrasil.mia.cx` without being connected to Netbird:

1. DNS resolves to Cloudflare
2. Janus Worker intercepts the request
3. Returns a friendly page explaining how to connect

## Deployment

**Via Cloudflare Dashboard:**

1. Create Worker in Cloudflare Dashboard
2. Add route: `*.yggdrasil.mia.cx/*`
3. Deploy code

**Via Wrangler CLI:**

```bash
cd apps/janus
npx wrangler deploy
```

## Configuration

### Worker Code

```javascript
const SERVICES = {
  "jellyfin.yggdrasil.mia.cx": {
    name: "Jellyfin",
    icon: "🎬",
    description: "Media streaming server",
  },
  "proxmox.yggdrasil.mia.cx": {
    name: "Proxmox",
    icon: "🖥️",
    description: "Hypervisor management",
  },
  "nextcloud.yggdrasil.mia.cx": {
    name: "Nextcloud",
    icon: "☁️",
    description: "File sync and collaboration",
  },
  "grafana.yggdrasil.mia.cx": {
    name: "Grafana",
    icon: "📊",
    description: "Monitoring dashboards",
  },
  // Add more as needed
}

export default {
  async fetch(request) {
    const url = new URL(request.url)
    const host = url.hostname
    const service = SERVICES[host] || {
      name: host.split(".")[0],
      icon: "🔒",
      description: "Internal service",
    }

    return new Response(
      `
<!DOCTYPE html>
<html>
<head>
  <title>${service.name} - Yggdrasil Access Required</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: system-ui, -apple-system, sans-serif;
      max-width: 500px;
      margin: 100px auto;
      padding: 20px;
      text-align: center;
      background: #0a0a0a;
      color: #e0e0e0;
    }
    .icon { font-size: 4rem; }
    h1 { margin: 0.5rem 0; color: #fff; }
    .subtle { color: #888; }
    a.btn {
      display: inline-block;
      margin-top: 1rem;
      padding: 0.75rem 1.5rem;
      background: #0066cc;
      color: white;
      text-decoration: none;
      border-radius: 6px;
    }
    a.btn:hover { background: #0077ee; }
  </style>
</head>
<body>
  <div class="icon">${service.icon}</div>
  <h1>${service.name}</h1>
  <p class="subtle">${service.description}</p>
  <p>This service is only available on the <strong>Yggdrasil</strong> network.</p>
  <p class="subtle">Connect via Netbird to access.</p>
  <a class="btn" href="https://netbird.io/download">Get Netbird</a>
</body>
</html>
    `,
      {
        headers: { "Content-Type": "text/html" },
      },
    )
  },
}
```

### Customization

- Add services to the `SERVICES` object
- Customize styling in the HTML template
- Add analytics tracking if desired
