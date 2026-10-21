# syntax=docker/dockerfile:1
# Keep the customization as a small patch over the exact upstream release.
FROM node:24-alpine AS web
RUN apk add --no-cache patch
WORKDIR /src
ADD --checksum=sha256:c21302a96b321611fcf67d7a18df54a98cbe11222a1308fd3526e96923d0c19f https://codeload.github.com/Willxup/cpa-usage-keeper/tar.gz/fc8cbde97fe6baa35189e51115716865ce377ec2 /tmp/upstream.tar.gz
RUN tar -xzf /tmp/upstream.tar.gz --strip-components=1 && rm /tmp/upstream.tar.gz
COPY overview.patch /tmp/overview.patch
RUN patch -p1 < /tmp/overview.patch
RUN npm --prefix web ci && npm --prefix web run build

FROM golang:1.26-alpine AS build
RUN apk add --no-cache build-base
WORKDIR /src
COPY --from=web /src/go.mod /src/go.sum ./
RUN go mod download
COPY --from=web /src/cmd ./cmd
COPY --from=web /src/internal ./internal
COPY --from=web /src/web/static.go ./web/static.go
COPY --from=web /src/web/dist ./web/dist
ARG VERSION=v2.0.0-yggdrasil
RUN CGO_ENABLED=1 go build -ldflags="-s -w -X cpa-usage-keeper/internal/version.Version=${VERSION}" -o /out/cpa-usage-keeper ./cmd/server/main.go

FROM ghcr.io/willxup/cpa-usage-keeper:v2.0.0@sha256:595cb942ba6993b7ae68a5bf97ce68e3ab35d56b4989051c5bccb29681e67129
LABEL org.opencontainers.image.source=https://github.com/mia-cx/yggdrasil-spec
COPY --from=build /out/cpa-usage-keeper /app/cpa-usage-keeper
