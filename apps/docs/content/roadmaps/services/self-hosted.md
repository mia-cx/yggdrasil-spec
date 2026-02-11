---
title: Self-Hosted Services Roadmap
---

# Self-Hosted Services Roadmap

A living list of candidate services to self-host: what they are, why host them, and rough effort. When you deploy one, add a row (and deity name) to [Naming](../../architecture/naming.md).

## Why self-host

- **Privacy and control** — Data stays at home; no vendor lock-in or surprise policy changes.
- **Learning and customization** — Tune storage, auth, and integration to your stack (e.g. Authentik, NFS, K3s).
- **Cost** — Avoid recurring SaaS fees for personal use.

Criteria here: prefer FOSS, container-friendly (Docker/K8s), and manageable ongoing maintenance. Dependencies (e.g. PostgreSQL, Redis) are noted where relevant.

---

## Notes / Obsidian (already in use)

**Published wiki:** [Quartz](https://quartz.jzhao.xyz/) builds the docs site from the Obsidian vault; that's the "wiki" for readers.

**Sync and live editing (internal):** [Obsidian LiveSync](https://github.com/vrtmrz/obsidian-livesync) ([docs](https://github.com/vrtmrz/obsidian-livesync#readme)) plugin with [MinIO](https://min.io/) (S3-compatible) ([docs](https://min.io/docs/)) as the backend. Use this for your own UX and internal devs — real-time sync and optional live collaboration. MinIO is already planned; deploy a bucket and credentials, then point LiveSync at the MinIO endpoint (path-style URL).

**External contributors:** They use **git** to push and pull the notes repo on [Forgejo](https://forgejo.org/) ([docs](https://forgejo.org/docs/)); no LiveSync. So: internal = LiveSync + MinIO, external = git + Forgejo.

---

## Music and media

| Service         | What it is                         | Why host it                                                                     | Effort / notes                                      |
| --------------- | ---------------------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------- |
| **[Navidrome](https://www.navidrome.org/)** ([docs](https://www.navidrome.org/docs/)) | Subsonic-compatible music server   | Stream your own library; no subscription; works with Substreamer, PlaySub, etc. | Easy. Single binary or Docker; metadata in SQLite.  |
| **[Calibre-Web](https://github.com/janeczku/calibre-web)** | Web UI for Calibre ebook libraries | Browse and read ebooks; no Kindle/Amazon tie-in; OPDS for readers.              | Easy if you already have Calibre; Docker or Python. |

Both fit "own your media" alongside Jellyfin (Thalia). Add a name in Naming when deployed.

---

## Finance and budgeting

| Service           | What it is                              | Why host it                                                                        | Effort / notes                                       |
| ----------------- | --------------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **[Firefly III](https://www.firefly-iii.org/)** ([docs](https://docs.firefly-iii.org/)) | Personal finance manager (double-entry) | Track spending, budgets, and accounts; data stays local; no bank linking required. | Medium. PHP + MySQL/PostgreSQL; import from CSV/API. |
| **[Actual Budget](https://actualbudget.com/)** ([docs](https://actualbudget.com/docs)) | Privacy-focused budgeting app           | Simple envelopes/budgeting; syncs across devices; open source.                     | Medium. Node + SQLite; self-hosted sync server.      |

Sensitive data; good candidate for internal-only or Authentik-protected access. Add a deity name when deployed (e.g. guardian or wealth figure).

---

## Analytics and monitoring

| Service       | What it is                             | Why host it                                                                  | Effort / notes                                          |
| ------------- | -------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------- |
| **[Plausible](https://plausible.io/)** ([self-host](https://plausible.io/docs/self-hosting)) | Privacy-friendly web analytics         | Lightweight, no cookies, GDPR-friendly; see traffic without Google.          | SaaS or self-host; self-host is more work.              |
| **[Umami](https://umami.is/)** ([docs](https://umami.is/docs)) | Open-source analytics (Plausible-like) | Same idea: simple, privacy-respecting page views and events.                 | Easy. Node + PostgreSQL; Docker or K8s.                 |
| **[Grafana](https://grafana.com/)** ([docs](https://grafana.com/docs/grafana/latest/)) | Dashboards and alerting                | Visualize metrics (Prometheus, Longhorn, Node Exporter); you had it planned. | Medium. Often paired with Prometheus; many Helm charts. |

Pick one analytics stack (Umami is simpler to self-host than Plausible). Grafana fits infra/monitoring. Add names in Naming when deployed.

---

## Bookmarks and utilities

| Service      | What it is                         | Why host it                                                                    | Effort / notes                     |
| ------------ | ---------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------- |
| **[Linkding](https://github.com/sissbruecker/linkding)** ([docs](https://github.com/sissbruecker/linkding#readme)) | Bookmark manager (tagging, search) | Replace browser sync or proprietary tools; exportable; optional read-it-later. | Easy. Single Docker image; SQLite. |

Add a deity name when deployed.

---

## Other candidates (planned or optional)

Already in the [Naming](../../architecture/naming.md) table with TBD or a suggested name:

- **[Forgejo](https://forgejo.org/)** ([docs](https://forgejo.org/docs/)) — Git hosting (Hephaestus?).
- **[Matrix](https://matrix.org/)** ([Synapse docs](https://matrix-org.github.io/synapse/latest/)) — Chat (federated).
- **[Home Assistant](https://www.home-assistant.io/)** ([docs](https://www.home-assistant.io/docs/)) — Home automation.
- **Federated social** — [Mastodon](https://joinmastodon.org/) ([self-host](https://docs.joinmastodon.org/admin/)), [Misskey](https://misskey-hub.net/) ([docs](https://misskey-hub.net/docs/)), [Cherrypick](https://github.com/kokonect-link/cherrypick) (Misskey fork).

Deploy when ready; fill in the name in Naming when you do.

---

## More homelab tools (optional)

Other popular self-hosted tools that might fit your stack. Add to Naming when you deploy.

| Tool | What it is | Why consider it |
| ---- | ---------- | ---------------- |
| **[Uptime Kuma](https://uptime.kuma.pet/)** ([GitHub](https://github.com/louislam/uptime-kuma)) | Uptime monitoring + status page | Pretty UI, many check types (HTTP, TCP, DNS, push), public or private status pages. |
| **[Paperless-ngx](https://paperless-ngx.com/)** ([docs](https://docs.paperless-ngx.com/)) | Document management (scan, OCR, tag) | Ingest PDFs/scans, full-text search, tag and archive; “paperless” home office. |
| **[Audiobookshelf](https://www.audiobookshelf.org/)** ([docs](https://www.audiobookshelf.org/docs)) | Audiobook server (like Navidrome for audiobooks) | Stream your own audiobooks; mobile apps; podcasts too. |
| **[Mealie](https://mealie.io/)** ([docs](https://docs.mealie.io/)) or **[Tandoor](https://tandoor.dev/)** | Recipe manager | Store recipes, meal plan, shopping lists; optional OCR from images. |
| **[Grocy](https://grocy.info/)** ([docs](https://docs.grocy.info/)) | Household inventory, chores, recipes | Track food expiry, chores, batteries; very “homelab life” if you like data. |
| **[Changedetection.io](https://changedetection.io/)** ([GitHub](https://github.com/dgtlmoon/changedetection.io)) | Watch URLs for changes | Get notified when a webpage or API response changes; RSS, JSON, etc. |
| **[Homer](https://github.com/bastienwirtz/homer)** / **[Dashy](https://dashy.to/)** / **[Homarr](https://homarr.dev/)** | Start page / dashboard | Single page with links to all your services; optional widgets and status. |
| **[n8n](https://n8n.io/)** ([self-host](https://docs.n8n.io/hosting/)) | Workflow automation (Zapier-like) | Self-hosted automations between apps, APIs, and services; no-code or code. |
| **[AdGuard Home](https://adguard.com/adguard-home/)** or **[Pi-hole](https://pi-hole.net/)** | DNS-level ad/tracker blocking | Network-wide blocking; optional DHCP; nice dashboards. |
| **[Kopia](https://kopia.io/)** ([docs](https://kopia.io/docs/)) or **[Restic](https://restic.net/)** | Backup (encrypted, dedup) | Back up VMs, dirs, or K8s; S3/MinIO compatible; scriptable. |
| **[Kavita](https://www.kavitareader.com/)** ([docs](https://wiki.kavitareader.com/)) | Ebook/comic reader server | Alternative to Calibre-Web; focused on reading (EPUB, CBZ); no Calibre dependency. |
| **[Prometheus](https://prometheus.io/)** ([docs](https://prometheus.io/docs/)) | Metrics (for Grafana) | Scrape metrics from nodes, K8s, Longhorn; you’ll want this if you run Grafana. |

---

## Summary

| Category    | Services listed here                                                     |
| ----------- | ------------------------------------------------------------------------ |
| Notes       | Quartz (publish) + LiveSync + MinIO (internal); git + Forgejo (external) |
| Wiki        | Bookstack, Outline (optional)                                            |
| Music/books | Navidrome, Calibre-Web, Audiobookshelf, Kavita (optional)                |
| Finance     | Firefly III, Actual Budget                                               |
| Analytics   | Plausible, Umami, Grafana, Prometheus (optional)                         |
| Bookmarks   | Linkding                                                                 |
| More        | Uptime Kuma, Paperless-ngx, Mealie/Tandoor, Grocy, Changedetection, Homer/Dashy/Homarr, n8n, AdGuard/Pi-hole, Kopia/Restic — see “More homelab tools” above |
| Elsewhere   | Forgejo, Matrix, Home Assistant, Fedi — see Naming table                 |

When you add a new service from this roadmap, create a row in the [Naming](../../architecture/naming.md) table and assign a deity name so it stays consistent with the rest of the stack.

---

## Quick links (project + docs)

| Service / tool | Project / homepage | Docs or self-host guide |
| --------------- | ------------------- | ------------------------- |
| Quartz | [quartz.jzhao.xyz](https://quartz.jzhao.xyz/) | [docs](https://quartz.jzhao.xyz/docs/) |
| Obsidian LiveSync | [GitHub](https://github.com/vrtmrz/obsidian-livesync) | [readme](https://github.com/vrtmrz/obsidian-livesync#readme) |
| MinIO | [min.io](https://min.io/) | [docs](https://min.io/docs/) |
| Forgejo | [forgejo.org](https://forgejo.org/) | [docs](https://forgejo.org/docs/) |
| Navidrome | [navidrome.org](https://www.navidrome.org/) | [docs](https://www.navidrome.org/docs/) |
| Calibre-Web | [GitHub](https://github.com/janeczku/calibre-web) | (README) |
| Firefly III | [firefly-iii.org](https://www.firefly-iii.org/) | [docs](https://docs.firefly-iii.org/) |
| Actual Budget | [actualbudget.com](https://actualbudget.com/) | [docs](https://actualbudget.com/docs) |
| Plausible | [plausible.io](https://plausible.io/) | [self-hosting](https://plausible.io/docs/self-hosting) |
| Umami | [umami.is](https://umami.is/) | [docs](https://umami.is/docs) |
| Grafana | [grafana.com](https://grafana.com/) | [docs](https://grafana.com/docs/grafana/latest/) |
| Linkding | [GitHub](https://github.com/sissbruecker/linkding) | (README) |
| Matrix (Synapse) | [matrix.org](https://matrix.org/) | [Synapse](https://matrix-org.github.io/synapse/latest/) |
| Home Assistant | [home-assistant.io](https://www.home-assistant.io/) | [docs](https://www.home-assistant.io/docs/) |
| Mastodon | [joinmastodon.org](https://joinmastodon.org/) | [admin/self-host](https://docs.joinmastodon.org/admin/) |
| Misskey | [misskey-hub.net](https://misskey-hub.net/) | [docs](https://misskey-hub.net/docs/) |
| Cherrypick | [GitHub](https://github.com/kokonect-link/cherrypick) | (Misskey fork) |
| Uptime Kuma | [uptime.kuma.pet](https://uptime.kuma.pet/) | [GitHub](https://github.com/louislam/uptime-kuma) |
| Paperless-ngx | [paperless-ngx.com](https://paperless-ngx.com/) | [docs](https://docs.paperless-ngx.com/) |
| Audiobookshelf | [audiobookshelf.org](https://www.audiobookshelf.org/) | [docs](https://www.audiobookshelf.org/docs) |
| Mealie | [mealie.io](https://mealie.io/) | [docs](https://docs.mealie.io/) |
| Tandoor | [tandoor.dev](https://tandoor.dev/) | (README) |
| Grocy | [grocy.info](https://grocy.info/) | [docs](https://docs.grocy.info/) |
| Changedetection.io | [changedetection.io](https://changedetection.io/) | [GitHub](https://github.com/dgtlmoon/changedetection.io) |
| Homer | [GitHub](https://github.com/bastienwirtz/homer) | (README) |
| Dashy | [dashy.to](https://dashy.to/) | (README) |
| Homarr | [homarr.dev](https://homarr.dev/) | [docs](https://homarr.dev/docs) |
| n8n | [n8n.io](https://n8n.io/) | [self-host](https://docs.n8n.io/hosting/) |
| AdGuard Home | [adguard.com/adguard-home](https://adguard.com/adguard-home/) | (README) |
| Pi-hole | [pi-hole.net](https://pi-hole.net/) | [docs](https://docs.pi-hole.net/) |
| Kopia | [kopia.io](https://kopia.io/) | [docs](https://kopia.io/docs/) |
| Restic | [restic.net](https://restic.net/) | [docs](https://restic.net/documentation.html) |
| Kavita | [kavitareader.com](https://www.kavitareader.com/) | [wiki](https://wiki.kavitareader.com/) |
| Prometheus | [prometheus.io](https://prometheus.io/) | [docs](https://prometheus.io/docs/) |
