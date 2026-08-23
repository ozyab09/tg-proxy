# tg-proxy-relay

Go-релей для WEB-прокси Telegram — серверная часть [tproxy-server](https://github.com/telegramdesktop/tproxy-server).
Релей принимает мультиплексированные фреймы WebView-транспорта (HTTPS/WebSocket) и соединяет каждый логический поток
с официальным MTProxy на том же хосте. DATA для него — непрозрачные байты, он не расшифровывает MTProxy-трафик.

Собирается из закреплённого коммита субмодуля `tproxy-server` (Go 1.26 → alpine 3.23), запускается
непривилегированным пользователем `tproxy` (uid 10001).

## Назначение

Образ — часть стека [tg-proxy](https://github.com/ozyab09/tg-proxy):

```
nginx (TLS) → tg-proxy-relay → tg-proxy-mtproto → дата-центры Telegram
```

Используется вместе с `ozyab/tg-proxy-mtproto` и nginx; отдельно от стека смысла не имеет.

## Запуск

Образ рассчитан на `network_mode: host` — релей принимает запросы только с loopback-адреса и слушает только
`127.0.0.1:8080/8081` (это проверяется в коде):

```bash
docker run -d --name tg-proxy-relay \
  --network host \
  -v /opt/tg-proxy/config/config.json:/etc/tproxy/config.json:ro \
  -v /opt/tg-proxy/config/profiles.json:/etc/tproxy/profiles.json:ro \
  -v /opt/tg-proxy/site:/srv/tproxy-site:ro \
  ozyab/tg-proxy-relay
```

## Монтируемые файлы

| Путь в контейнере | Назначение |
|---|---|
| `/etc/tproxy/config.json` | конфигурация релея (`public_hostname`, лимиты, таймауты) |
| `/etc/tproxy/profiles.json` | профили с MTProxy-секретами и бэкендами — **chmod 0400, владелец uid 10001** |
| `/srv/tproxy-site` | статический сайт (обязателен `index.html`), отдаётся из памяти |

## Порты

- `8080` — публичный шлюз (через него проксирует nginx);
- `8081` — административный (только loopback): `/healthz`, `/readyz`, `/metrics`.

## Healthcheck

```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8081/healthz"]
```

## Теги

- `latest` — последний релиз (обновляется только тегом `v*`);
- `v<версия>` — релизные теги;
- `<sha12>` — dev-образы (PR и мёрджи в main).
