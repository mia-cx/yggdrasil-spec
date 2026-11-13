# syntax=docker/dockerfile:1
# Keep the deployed upstream release; add only weekly reset recovery from our fork.
FROM golang:1.26-bookworm AS build
WORKDIR /src
ADD --checksum=sha256:d920e423a0cf6f0b15e78b24079876c095a620183a850a1ecae4e21e83279bfd https://codeload.github.com/mia-riezebos/CLIProxyAPI/tar.gz/1cf6e0a75604183e462d41367716b7a2d24d46c1 /tmp/source.tar.gz
RUN tar -xzf /tmp/source.tar.gz --strip-components=1 && rm /tmp/source.tar.gz
RUN go test ./sdk/cliproxy/auth ./internal/config
RUN CGO_ENABLED=1 go build -buildvcs=false -ldflags="-s -w -X main.Version=v8.0.69-yggdrasil-weekly-reset -X main.Commit=1cf6e0a75604183e462d41367716b7a2d24d46c1" -o /out/CLIProxyAPI ./cmd/server

FROM eceasy/cli-proxy-api:v8.0.69@sha256:e77c1eecc0e364c1885a4441cdd6487ef305852851f70da723548736065c2e9b
LABEL org.opencontainers.image.source=https://github.com/mia-cx/yggdrasil-spec
COPY --from=build /out/CLIProxyAPI /CLIProxyAPI/CLIProxyAPI
