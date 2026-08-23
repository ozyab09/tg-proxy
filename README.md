# tg-proxy

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![relay](https://img.shields.io/docker/pulls/ozyab/tg-proxy-relay.svg)](https://hub.docker.com/r/ozyab/tg-proxy-relay)
[![mtproto](https://img.shields.io/docker/pulls/ozyab/tg-proxy-mtproto.svg)](https://hub.docker.com/r/ozyab/tg-proxy-mtproto)

Docker-развёртывание [tproxy-server](https://github.com/telegramdesktop/tproxy-server) —
серверной части WEB-прокси для Telegram. Один публичный HTTPS-сайт, мост
открывается только по точному запросу `/?bridge=<capability>`, а логические
потоки мультиплексируются через WebView-транспорт и пересылаются на
официальный MTProxy.

Стек: **nginx** (TLS + Let's Encrypt) → **Go-релей** (tproxy-server) →
**официальный MTProxy**. Всё в `docker compose`, все сервисы — в host-сети
(релей принимает только loopback-соединения, поэтому конфиг не меняется).

## Требования

- сервер **x86_64** с публичным IPv4: Ubuntu/Debian (apt) или CentOS/RHEL (dnf/yum);
- root или `sudo`;
- свободные TCP 80/443;
- домен с A-записью на сервер — или используйте `<IP>.sslip.io` (без DNS-настройки).

## Быстрая установка

На свежем сервере **Ubuntu/Debian или CentOS/RHEL (x86_64)** с публичным IP:

```bash
curl -fsSL https://raw.githubusercontent.com/ozyab09/tg-proxy/main/install.sh | sudo bash
```

Скрипт:

1. проверяет root, архитектуру (MTProxy — только x86_64), ОС и свободные
   порты 80/443;
2. устанавливает Docker и Compose-плагин;
3. спрашивает домен (Enter — `<public-ip>.sslip.io`) и MTProxy-секрет
   (Enter — сгенерирует и покажет один раз);
4. скачивает репозиторий (с субмодулем `tproxy-server`) в `/opt/tg-proxy`;
5. генерирует `.env`, `config/config.json`, `config/profiles.json`
   (chmod 0400), `nginx/tproxy.conf`;
6. скачивает официальные `proxy-secret` и `proxy-multi.conf` Telegram;
7. настраивает фаервол: открывает 80/443, **закрывает 2398/8888 снаружи**
   (nftables на Debian/Ubuntu, firewalld на CentOS/RHEL);
8. поднимает стек, выпускает сертификат Let's Encrypt и ставит
   systemd-таймер ежедневного продления.

Повторный запуск безопасен: домен, секрет, сайт и сертификат сохраняются.

## Клиент Telegram

WEB-прокси принимает два значения — хостнейм и секрет:

```text
Hostname: <ваш домен>
Secret:   <32 hex-символа>
```

Готовая ссылка (выводится в конце установки):

```text
https://t.me/webproxy?server=<домен>&secret=<секрет>
```

## Как это устроено

```text
Интернет :80/:443
      │
      ▼
 nginx (host-сеть) ── TLS, Let's Encrypt, reverse proxy всех путей
      │  proxy_pass http://127.0.0.1:8080
      ▼
 tproxy-relay (host-сеть) ── слушает 127.0.0.1:8080/8081
      │  TCP-потоки на 127.0.0.1:2398
      ▼
 tproxy-mtproxy (host-сеть) ── официальный MTProxy 0.0.0.0:2398 (+8888 stats)
      │                          снаружи закрыт фаерволом
      ▼
  дата-центры Telegram
```

- **nginx** — только TLS-терминатор. Ничего не раздаёт статикой: все пути
  уходят в релей, который сам отдаёт сайт из памяти. `access_log off` — в URL
  моста живёт capability, логировать его нельзя.
- **релей** — принимает запросы только с loopback (проверка в коде), поэтому
  всё работает в `network_mode: host`, а конфиг релея не изменён.
- **MTProxy** — собирается из закреплённого коммита
  `f36d8af769ffaeac36978d38c2c0f6d1104c2137` внутри ubuntu-образа, поэтому
  хост-ОС (Ubuntu или CentOS) для него не важна.

## Образы Docker Hub

Собираются GitHub Actions из этого репозитория (исходник релея — из
субмодуля, закреплённого коммита):

| Образ | Содержимое |
|---|---|
| `ozyab/tg-proxy-relay` | Go-релей tproxy-server (alpine) |
| `ozyab/tg-proxy-mtproto` | официальный MTProxy (ubuntu 24.04) |

Политика тегов:

| Событие | Теги образа |
|---|---|
| PR открыт/обновлён | `<sha12>` (хэш head-коммита) |
| Пуш в `main` (MR смержен) | `<sha12>` (хэш merge-коммита) |
| Тег `v*` (например `v1.0.1`) | `<версия>` **и** `latest` |

`latest` обновляется **только** релизным тегом. Локальная сборка:
`docker compose build`.

## Как выпустить новую версию

1. Сделайте изменения, откройте PR, дождитесь мёрджа в `main` —
   автоматически соберётся dev-образ с хэшем коммита
   (`ozyab/tg-proxy-relay:<sha12>`).
2. Когда готовы к релизу, создайте тег и запушьте его:

   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```

   Workflow соберёт `ozyab/tg-proxy-relay:v1.0.1` + `latest` (и то же для
   `tg-proxy-mtproto`).

## Обновление сервера

Установленный стек всегда тянет `latest`:

```bash
cd /opt/tg-proxy
docker compose pull
docker compose up -d
```

Чтобы закрепить конкретную версию (например для отката), укажите тег в
`docker-compose.yml` вместо `image: ozyab/tg-proxy-relay`:

```yaml
image: ozyab/tg-proxy-relay:v1.0.1
```

и повторите `docker compose pull && docker compose up -d`.

## Ручная настройка GitHub Actions

В настройках репозитория **Settings → Secrets and variables → Actions**
добавьте:

| Secret | Значение |
|---|---|
| `DOCKERHUB_USERNAME` | ваш логин Docker Hub |
| `DOCKERHUB_TOKEN` | access token (Account Settings → Security → New Access Token) |

Workflow запускается на push в `main`, теги `v*` и вручную
(workflow_dispatch).

## Замена сайта

Релей отдаёт сайт из памяти, читая его при старте:

```bash
cd /opt/tg-proxy
# замените файлы в site/ (обязателен index.html)
docker compose up -d --force-recreate relay
```

Важно: релей отдаёт публичные страницы с CSP `style-src 'self'` — inline
`<style>` и `<script>` блокируются. Стартовый сайт (`site-starter/index.html`)
сделан одной страницей без внешних ресурсов. Свой сайт можно делать обычным
(несколько `.html`, `styles.css`), но без inline-стилей и внешних ресурсов.

## Управление и проверка

```bash
cd /opt/tg-proxy
docker compose ps
docker compose logs -f relay

curl -fsS http://127.0.0.1:8081/healthz
curl -fsS http://127.0.0.1:8081/readyz
curl -fsS http://127.0.0.1:8081/metrics
curl -fsS http://127.0.0.1:8888/stats          # статистика MTProxy

# порты 2398/8888 должны быть недоступны снаружи:
nc -vz -w 3 <SERVER_IP> 2398
nc -vz -w 3 <SERVER_IP> 8888
```

Лимиты релея — в `/opt/tg-proxy/config/config.json` (после изменения:
`docker compose up -d --force-recreate relay`).

## Безопасность

- Фаервол на хосте — **второй рубеж**; первый — firewall провайдера
  (открыть только 80/443).
- Секрет MTProxy хранится в `.env` (chmod 600) и в `config/profiles.json`
  (chmod 0400, владелец — uid релея 10001).
- Не включайте логирование URI на nginx (отключено в конфиге): в query моста
  и заголовках WebSocket живут capability и bearer.
- MTProxy слушает `0.0.0.0:2398` (у него нет опции bind) — поэтому правило
  drop 2398/8888 обязательно; не доверяйте только ему, закрывайте и на
  провайдере.
- Секрет передаётся MTProxy через аргумент `-S` (как в оригинальном
  развёртывании) — виден в аргументах процесса; не давайте посторонним
  доступ к хосту.

## Устранение неполадок

- **Сертификат не выпускается:** проверьте, что домен (или sslip.io-имя)
  резолвится в публичный IP сервера и что 80/443 открыты снаружи.
- **`/readyz` = 503:** MTProxy не поднялся — `docker compose logs mtproxy`,
  проверьте `mtproxy-data/proxy-secret` и `mtproxy-data/proxy-multi.conf`.
- **Клиент не подключается:** хостнейм и секрет должны точно совпадать с
  профилем; capability выводится из пары hostname+secret.
- **Сайт работает, мост нет:** проверяйте только санитизированные статусы и
  метрики, никогда не логируйте URL моста.

## Структура

```text
.
├── tproxy-server/            # git submodule → telegramdesktop/tproxy-server
├── Dockerfile                # образ релея
├── mtproxy/Dockerfile        # образ официального MTProxy
├── nginx/
│   ├── nginx.conf            # базовый конфиг (access_log off)
│   └── tproxy.conf.tmpl      # шаблон vhost (__DOMAIN__ → install.sh)
├── site-starter/index.html   # стартовый сайт (одна страница)
├── docker-compose.yml
├── .env.example
├── install.sh                # установщик (скачивается с GitHub)
├── renew-cert.sh             # продление сертификата (systemd-таймер)
├── firewall.nft              # nftables: drop 2398/8888 снаружи
├── deploy/tg-proxy-firewall.service
└── .github/workflows/docker-image.yml
```

Подробности протокола и архитектуры — в `tproxy-server/PROTOCOL.md` и
`tproxy-server/PLAN.md`.
