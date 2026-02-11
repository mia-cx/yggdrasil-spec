---
title: Project Ideas
---

Future projects and experiments to revisit. Not part of the homelab runbooks; just reminders.

---

## Jelly-Clipper as browser extension (client-side)

**Idea:** Take [Jelly-Clipper](https://github.com/arnolicious/jelly-clipper) (companion webapp for creating and sharing clips from Jellyfin content) and reimagine it as a **client-side browser extension** instead of a hosted app.

- **Current:** Hosted SvelteKit app; server downloads from Jellyfin, stores clips, serves them.
- **Target:** Browser extension that runs in the user’s browser; use **ffmpeg-wasm** for encoding clips locally so no server is needed for clip creation or storage (clips could be exported/downloaded or synced to a backend of choice later).

**Links:**

- [Jelly-Clipper (GitHub)](https://github.com/arnolicious/jelly-clipper)
- [ffmpeg.wasm](https://ffmpegwasm.net/) — FFmpeg compiled to WebAssembly for in-browser encoding.
