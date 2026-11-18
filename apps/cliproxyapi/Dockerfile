# syntax=docker/dockerfile:1
# Keep the deployed upstream release; add only weekly reset recovery from our fork.
FROM golang:1.26-bookworm AS build
WORKDIR /src
ADD --checksum=sha256:56c4f020e2a594a67d18a4c75510cef9f38366af5c00bbeec7c2aaf69b99dd05 https://codeload.github.com/mia-riezebos/CLIProxyAPI/tar.gz/cfb19c18378d40bfa950af1436e2d7475145a44f /tmp/source.tar.gz
RUN tar -xzf /tmp/source.tar.gz --strip-components=1 && rm /tmp/source.tar.gz
RUN go test ./sdk/cliproxy/auth ./internal/config
RUN CGO_ENABLED=1 go build -buildvcs=false -ldflags="-s -w -X main.Version=v8.0.77-yggdrasil-weekly-reset -X main.Commit=cfb19c18378d40bfa950af1436e2d7475145a44f" -o /out/CLIProxyAPI ./cmd/server

FROM eceasy/cli-proxy-api:v8.0.77@sha256:2acf44fbadf9933a04e971048b4c2ddd184ce6e3ea08fc2dc25354f3a365f5ab
LABEL org.opencontainers.image.source=https://github.com/mia-cx/yggdrasil-spec
COPY --from=build /out/CLIProxyAPI /CLIProxyAPI/CLIProxyAPI
