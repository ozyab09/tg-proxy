# tg-proxy-relay

Go relay for the Telegram WEB proxy — the server side of [tproxy-server](https://github.com/telegramdesktop/tproxy-server).
The relay accepts multiplexed frames of the WebView transport (HTTPS/WebSocket) and connects each logical stream
to the official MTProxy on the same host. DATA is opaque bytes to it — it does not decrypt MTProxy traffic.

Built from the pinned commit of the `tproxy-server` submodule (Go 1.26 → alpine 3.23), runs as the
unprivileged user `tproxy` (uid 10001).

## Purpose

The image is part of the [tg-proxy](https://github.com/ozyab09/tg-proxy) stack:

```
nginx (TLS) → tg-proxy-relay → tg-proxy-mtproto → Telegram data centers
```

It is meant to be used together with `ozyab/tg-proxy-mtproto` and nginx; on its own it is useless.

## Run

The image expects `network_mode: host` — the relay only accepts connections from loopback and listens on
`127.0.0.1:8080/8081` only (this is enforced in code):

```bash
docker run -d --name tg-proxy-relay \
  --network host \
  -v /opt/tg-proxy/config/config.json:/etc/tproxy/config.json:ro \
  -v /opt/tg-proxy/config/profiles.json:/etc/tproxy/profiles.json:ro \
  -v /opt/tg-proxy/site:/srv/tproxy-site:ro \
  ozyab/tg-proxy-relay
```

## Mounted files

| Path in container | Purpose |
|---|---|
| `/etc/tproxy/config.json` | relay configuration (`public_hostname`, limits, timeouts) |
| `/etc/tproxy/profiles.json` | profiles with MTProxy secrets and backends — **chmod 0400, owned by uid 10001** |
| `/srv/tproxy-site` | static site (requires `index.html`), served from memory |

## Ports

- `8080` — public gateway (nginx proxies through it);
- `8081` — admin (loopback only): `/healthz`, `/readyz`, `/metrics`.

## Healthcheck

```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8081/healthz"]
```

## Tags

- `latest` — the latest release (moves only on `v*` tags);
- `v<version>` — release tags;
- `<sha12>` — dev images (PRs and merges into main).
