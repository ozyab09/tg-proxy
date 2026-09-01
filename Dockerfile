# syntax=docker/dockerfile:1

# tg-proxy relay image.
# The relay source comes from the pinned tproxy-server git submodule, so the
# build is reproducible: checkout with `submodules: recursive` and the commit
# recorded in the parent repository is what gets compiled.

FROM golang:1.27 AS build
WORKDIR /src
COPY tproxy-server/ ./tproxy-server/
WORKDIR /src/tproxy-server
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/tproxy-server ./cmd/tproxy-server

FROM alpine:3.23
RUN adduser -D -H -u 10001 tproxy
COPY --from=build /out/tproxy-server /usr/local/bin/tproxy-server
USER tproxy
EXPOSE 8080 8081
ENTRYPOINT ["tproxy-server"]
CMD ["-config", "/etc/tproxy/config.json"]
