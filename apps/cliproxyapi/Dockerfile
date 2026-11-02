# syntax=docker/dockerfile:1
# Keep the deployed upstream release; add only weekly reset recovery from our fork.
FROM golang:1.26-bookworm AS build
WORKDIR /src
ADD --checksum=sha256:49b7bc84b3b41238ddbddba953b02d74f6d3ed63a2a625f4d37fd700ab3a8432 https://codeload.github.com/mia-riezebos/CLIProxyAPI/tar.gz/33a07d5352942c6a925888e02246270e215ba1e2 /tmp/source.tar.gz
RUN tar -xzf /tmp/source.tar.gz --strip-components=1 && rm /tmp/source.tar.gz
RUN go test ./sdk/cliproxy/auth ./internal/config
RUN CGO_ENABLED=1 go build -buildvcs=false -ldflags="-s -w -X main.Version=v8.0.45-yggdrasil-weekly-reset -X main.Commit=33a07d5352942c6a925888e02246270e215ba1e2" -o /out/CLIProxyAPI ./cmd/server

FROM eceasy/cli-proxy-api:v8.0.45@sha256:ce9583e43fb56e632a279b79e6203bbdedc34f09900a60fc0ced0e3f255bc63c
LABEL org.opencontainers.image.source=https://github.com/mia-cx/yggdrasil-spec
COPY --from=build /out/CLIProxyAPI /CLIProxyAPI/CLIProxyAPI
