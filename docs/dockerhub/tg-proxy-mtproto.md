# tg-proxy-mtproto

Официальный [MTProxy](https://github.com/TelegramMessenger/MTProxy) Telegram, собранный **без изменений** из
закреплённого коммита `f36d8af769ffaeac36978d38c2c0f6d1104c2137` (ubuntu 24.04, gcc 13). Только **x86_64**.

Образ — часть стека [tg-proxy](https://github.com/ozyab09/tg-proxy): релей `ozyab/tg-proxy-relay` соединяет
каждый логический поток с этим бэкендом по `127.0.0.1:2398`.

## Запуск

```bash
docker run -d --name tg-proxy-mtproxy \
  --network host \
  -v /opt/tg-proxy/config/proxy-multi.conf:/etc/mtproxy/proxy-multi.conf:ro \
  -v /opt/tg-proxy/mtproxy-data:/var/lib/mtproxy \
  ozyab/tg-proxy-mtproto
```

## Конфигурация

`proxy-multi.conf` — [формат Telegram](https://github.com/TelegramMessenger/MTProxy#configuration): каждая строка —
`порт секрет теги?`, например `2398 SECRET dd`. Секрет должен совпадать с профилем в `profiles.json` релея.

## Порты

- `2398` — клиентский порт MTProxy, слушается на `0.0.0.0` (для Docker нужен host-режим или проброс
  bind-адреса). **Обязательно закрыть снаружи** фаерволом (nftables/firewalld) и на firewall провайдера.
- `8888` — статистика (`curl http://127.0.0.1:8888/stats`), по документации MTProxy доступна только через loopback.

Процесс работает под непривилегированным пользователем `mtproxy` (uid 10002).

## Healthcheck

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8888/stats >/dev/null 2>&1 || bash -c 'exec 3<>/dev/tcp/127.0.0.1/2398'"]
```

## Теги

- `latest` — последний релиз (обновляется только тегом `v*`);
- `v<версия>` — релизные теги;
- `<sha12>` — dev-образы (PR и мёрджи в main).
