# tg-proxy-mtproto

Official [MTProxy](https://github.com/TelegramMessenger/MTProxy) for Telegram, built **unchanged** from the
pinned commit `f36d8af769ffaeac36978d38c2c0f6d1104c2137` (ubuntu 24.04, gcc 13). **x86_64 only**.

The image is part of the [tg-proxy](https://github.com/ozyab09/tg-proxy) stack: the relay
`ozyab/tg-proxy-relay` connects each logical stream to this backend at `127.0.0.1:2398`.

## Run

```bash
docker run -d --name tg-proxy-mtproxy \
  --network host \
  -v /opt/tg-proxy/config/proxy-multi.conf:/etc/mtproxy/proxy-multi.conf:ro \
  -v /opt/tg-proxy/mtproxy-data:/var/lib/mtproxy \
  ozyab/tg-proxy-mtproto
```

## Configuration

`proxy-multi.conf` — [Telegram format](https://github.com/TelegramMessenger/MTProxy#configuration): one line per
proxy, `port secret tags?`, e.g. `2398 SECRET dd`. The secret must match the profile in the relay's `profiles.json`.

## Ports

- `2398` — MTProxy client port, listens on `0.0.0.0` (requires host networking or a bind-address
  workaround in Docker). **Must be firewalled off from the outside** (nftables/firewalld and the hosting
  provider's firewall).
- `8888` — stats (`curl http://127.0.0.1:8888/stats`), per MTProxy docs accessible via loopback only.

The process runs as the unprivileged user `mtproxy` (uid 10002).

## Healthcheck

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8888/stats >/dev/null 2>&1 || bash -c 'exec 3<>/dev/tcp/127.0.0.1/2398'"]
```

## Tags

- `latest` — the latest release (moves only on `v*` tags);
- `v<version>` — release tags;
- `<sha12>` — dev images (PRs and merges into main).
