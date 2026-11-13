# CLIProxyAPI weekly reset recovery

This image builds the deployed v8.0.69 release with
[our weekly reset recovery](https://github.com/mia-riezebos/CLIProxyAPI/compare/f7ae8feeb3710319f524730849fbe32fde1751e4...1cf6e0a75604183e462d41367716b7a2d24d46c1),
kept on the fork's `yggdrasil/v8.0.69` branch.
The Dockerfile pins the fork source commit and archive checksum, then replaces
the binary in the same upstream runtime image. Auth-manager and config tests
run during the build.

`.github/workflows/cliproxyapi.yaml` publishes an amd64 image tagged with this
repository's full commit. Pin the resulting digest in
`argocd/cliproxyapi/deployment.yaml`. Publishing an image does not deploy it.

The fork adds `upstream.codex.auto-reset-weekly-limit`, defaulting to false.
Our seed config enables it. Existing installations require an authenticated
`PUT /v8/management/config/upstream/codex/auto-reset-weekly-limit` with JSON
body `true` after deploying the image; this changes only that field and
persists it on CPA's volume. Set it to `false` to disable automatic redemption.

The recovery contract and journal are described in the
[fork documentation](https://github.com/mia-riezebos/CLIProxyAPI/blob/1cf6e0a75604183e462d41367716b7a2d24d46c1/docs/codex-weekly-reset.md).
Keep future updates based on the selected upstream release, and retain its
existing model catalog and provider behavior unless an upgrade is requested.
