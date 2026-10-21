# Yggdrasil Keeper overview

This image applies `overview.patch` to CPA Usage Keeper v2.0.0, pinned by
source archive checksum and commit. The backend API stays upstream. The patch
changes the overview to six metric cells with angular sparklines and a daily
averages strip, using Keeper's actual overview data and existing palette.

```sh
docker build -t cpa-usage-keeper:yggdrasil apps/cpa-usage-keeper
```

`.github/workflows/cpa-usage-keeper.yaml` publishes an amd64 image to
`ghcr.io/mia-cx/yggdrasil-cpa-usage-keeper`, tagged with the full Git commit.
Make the package public after its first publication so K3s can pull without
registry credentials. Pin the resulting image digest in
`argocd/cliproxyapi/keeper.yaml`; publishing an image does not deploy it.

To upgrade upstream, regenerate the patch against the chosen release, update
the source commit/archive checksum and runtime image digest in the Dockerfile,
then run upstream's web typecheck, lint, tests and build. Verify populated and
empty overviews at desktop and phone widths before changing the deployed digest.

Upstream is [Willxup/cpa-usage-keeper](https://github.com/Willxup/cpa-usage-keeper),
licensed under MIT; its notice is retained in `LICENSE`.
