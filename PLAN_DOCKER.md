# План: публикация tproxy-server на GitHub + Docker-развёртывание

## 1. Цель

Опубликовать проект в GitHub и дать пользователям однокомандную установку:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sudo bash
```

Скрипт проверяет систему (Ubuntu/Debian или CentOS/RHEL), ставит Docker,
раскладывает по папкам `docker-compose.yml`, конфиг **nginx** и конфигурацию
релея, спрашивает домен (или предлагает `sslip.io`) и настраивает
Let's Encrypt.

## 2. Ключевые ограничения кода, которые определяют архитектуру

При изучении `tproxy-server` найдены два жёстких требования, которые
нельзя обойти без форка — поэтому они диктуют выбор схемы сети:

1. **Релей принимает запросы только с loopback-адреса.**
   `internal/server/server.go:626` — `clientIP()` отвергает любой запрос,
   чей TCP-peer (`RemoteAddr`) не является loopback.
   → nginx **не может** ходить в релей по bridge-сети (172.x.x.x). Только
   loopback или `network_mode: host`.

2. **Конфиг релея принимает только loopback-адреса для listen/admin.**
   `internal/config/config.go:413` — `validateLoopbackAddress()`.
   → в контейнере нельзя просто указать `0.0.0.0:8080`.

**Решение: `network_mode: host` для всех трёх сервисов.** Тогда:

- релей слушает `127.0.0.1:8080` / `127.0.0.1:8081` — конфиг не меняется вовсе;
- nginx слушает 80/443 хоста и проксирует на `127.0.0.1:8080` — релей видит
  loopback-peer ✓;
- MTProxy по-прежнему слушает `0.0.0.0:2398` (+статистика `8888`) — закрываем
  фаерволом, как в оригинале;
- **субмодуль `tproxy-server` не требует ни одной правки** — образ собирается
  из неизменённого исходника.

Побочный эффект: контейнеры разделяют сетевой стек хоста (порты не
перемапливаются). Это нормально — сервер выделенный, как и в оригинальном
развёртывании.

## 3. Схема

```text
Интернет :80/:443
      │
      ▼
 nginx (container, host net)   ← TLS, Let's Encrypt, reverse proxy
      │  proxy_pass http://127.0.0.1:8080  (все пути)
      ▼
 tproxy-relay (container, host net)         слушает 127.0.0.1:8080/8081
      │  TCP-потоки на 127.0.0.1:2398
      ▼
 tproxy-mtproxy (container, host net)        официальный MTProxy 0.0.0.0:2398
      │                                        (наружу закрыт фаерволом)
      ▼
  дата-центры Telegram
```

Все три сервиса в одном `docker-compose.yml`, host-сеть, restart-политика,
healthcheck'и. Сайт отдаёт сам релей из памяти (`public_dir`) — nginx ничего
не раздаёт статикой, он только TLS-терминатор и прокси. Это сохраняет
главное свойство оригинальной архитектуры: один публичный шлюз, без второго
пробуемого транспортного пути.

## 4. Репозитории и submodule

```text
github.com/<USER>/tproxy-server     ← существующий проект (сейчас 0 коммитов!)
github.com/<USER>/tproxy-docker     ← НОВЫЙ репозиторий (название уточнить)
```

Шаг 0: закоммитить `tproxy-server` и запушить как отдельный репозиторий —
submodule обязан указывать на опубликованный remote.

Структура нового репозитория `tproxy-docker`:

```text
tproxy-docker/
├── tproxy-server/            # git submodule → github.com/<USER>/tproxy-server
├── Dockerfile                # образ релея (сборка из ./tproxy-server)
├── mtproxy/
│   └── Dockerfile            # образ официального MTProxy (закреплённый коммит)
├── nginx/
│   ├── tproxy.conf           # шаблон vhost, домен подставляется install.sh
│   └── nginx.conf            # базовый конфиг (access_log off и т.п.)
├── site/                     # стартовый минимальный сайт (index.html, 404 и т.д.)
├── docker-compose.yml
├── .env.example
├── install.sh
├── .github/workflows/docker-image.yml
└── README.md
```

## 5. Образы (Docker Hub)

Один Docker Hub-репозиторий `docker.io/<USER>/tproxy`, два тега: `relay` и
`mtproxy` (плюс теги по SHA коммита). Оба собираются в GitHub Actions.

### 5.1 `Dockerfile` — образ релея

```dockerfile
FROM golang:1.20 AS build
WORKDIR /src
COPY tproxy-server/ ./tproxy-server/       # субмодуль
WORKDIR /src/tproxy-server
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" \
    -o /out/tproxy-server ./cmd/tproxy-server

FROM alpine:3.19
RUN adduser -D -H tproxy
COPY --from=build /out/tproxy-server /usr/local/bin/tproxy-server
USER tproxy
EXPOSE 8080 8081
ENTRYPOINT ["tproxy-server"]
CMD ["-config", "/etc/tproxy/config.json"]
```

### 5.2 `mtproxy/Dockerfile` — образ официального MTProxy

Двухстадийный: сборка на `ubuntu:22.04` (build-essential, libssl-dev,
zlib1g-dev), `git clone` + checkout закреплённого коммита
`f36d8af769ffaeac36978d38c2c0f6d1104c2137` (как в оригинальном
`deploy/install.sh`), `make`; финальный слой — `ubuntu:22.04`, пользователь
`mtproxy`, только бинарь. **Важно: MTProxy работает только на x86_64** —
install.sh проверяет `uname -m`.

## 6. docker-compose.yml

```yaml
services:
  nginx:
    image: nginx:1.27-alpine
    network_mode: host
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/tproxy.conf:/etc/nginx/conf.d/tproxy.conf:ro
      - ./letsencrypt:/etc/letsencrypt
      - ./certbot-webroot:/var/www/certbot
    depends_on: [relay]
    restart: unless-stopped

  relay:
    image: docker.io/<USER>/tproxy:relay
    network_mode: host
    volumes:
      - ./config/config.json:/etc/tproxy/config.json:ro
      - ./config/profiles.json:/etc/tproxy/profiles.json:ro
      - ./site:/srv/tproxy-site:ro
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8081/healthz"]
    restart: unless-stopped

  mtproxy:
    image: docker.io/<USER>/tproxy:mtproxy
    network_mode: host
    env_file: .env                       # MTPROXY_SECRET (chmod 600)
    command: >
      -u mtproxy -p 8888 -H 2398 -S ${MTPROXY_SECRET}
      --aes-pwd /etc/mtproxy/proxy-secret
      /etc/mtproxy/proxy-multi.conf -M 1 -C 4096
    volumes:
      - ./mtproxy-data:/etc/mtproxy:ro    # proxy-secret + proxy-multi.conf
    restart: unless-stopped
```

Конфиги релея (`config.json`, `profiles.json`) генерирует install.sh
(права 0400): `listen`/`admin_listen` остаются loopback (см. п. 2),
`public_hostname` = домен, `public_dir` = `/srv/tproxy-site`,
`profiles_file` = `/etc/tproxy/profiles.json`.

## 7. nginx (вместо Caddy)

nginx — чистый TLS-терминатор и reverse proxy **всех** путей на
`127.0.0.1:8080`. Обязательные параметры (выведены из требований релея):

```nginx
server {
  listen 80;
  server_name <DOMAIN>;
  location /.well-known/acme-challenge/ { root /var/www/certbot; }
  location / { return 301 https://$host$request_uri; }
}

server {
  listen 443 ssl http2;
  server_name <DOMAIN>;

  ssl_certificate     /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;

  access_log off;                     # в URL моста — capability, логировать нельзя

  client_max_body_size 2m;            # дефолт nginx 1m < лимита релея 2 MiB!

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;                    # релей требует оригинальный Host
    proxy_set_header X-Forwarded-For $remote_addr;  # ровно один IP — иначе релей отклонит
    proxy_set_header Upgrade $http_upgrade;         # WebSocket-режимы канала
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 40s;   # > long_poll релея (25s), иначе парковка обрывается
    proxy_send_timeout 40s;
    proxy_buffering off;
  }

  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
```

Что нельзя делать (из PLAN.md/PUBLIC_SITE.md):

- не добавлять глобально `X-Frame-Options`/COOP/COEP — у моста свой CSP;
- не включать логирование URI/заголовков (в query — capability);
- не сжимать `application/octet-stream` (дефолтный `gzip_types` nginx это уже
  исключает, как и у Caddy).

## 8. install.sh — пошаговый сценарий

Запускается от root одной командой (`curl … | sudo bash`). Порядок:

1. **Проверки**: root; `uname -m` = x86_64 (MTProxy); свободны ли 80/443.
2. **Определение ОС**: `apt` (Debian/Ubuntu) или `dnf`/`yum` (CentOS/RHEL).
   Дальше ОС почти не важна — всё собирается в ubuntu-образах Docker;
   различаются только установка Docker и фаервол.
3. **Установка Docker**: официальный скрипт `get.docker.com` + плагин compose,
   `systemctl enable --now docker`.
4. **Домен**: спрашивает у пользователя домен **или** предлагает по умолчанию
   `<public-ip>.sslip.io` (бесплатный wildcard-DNS → IP сервера, Let's Encrypt
   работает сразу). Проверяет, что домен резолвится в публичный IP сервера;
   при несовпадении — предупреждение, но продолжает (sslip.io всегда совпадает).
5. **Секрет MTProxy**: спрашивает у пользователя (ввод без эха, `read -s`)
   или генерирует `openssl rand -hex 16` и печатает один раз.
6. **Скачивание репозитория**: `git clone --recursive` в `/opt/tproxy`
   (все файлы — из GitHub, включая `docker-compose.yml` и конфиг nginx).
7. **Генерация файлов**: `.env` (секрет, права 600), `config.json` +
   `profiles.json` (0400, loopback-адреса, домен), `nginx/tproxy.conf`
   (подстановка домена в шаблон), стартовый `site/` (если пользователь не
   подложил свой).
8. **MTProxy-данные**: скачивает `proxy-secret` и `proxy-multi.conf`
   с `https://core.telegram.org/getProxyConfig` (как оригинальный
   `refresh-mtproxy-config.sh`), кладёт в `mtproxy-data/`.
9. **Фаервол**: открыть 80/443; **закрыть 2398 и 8888 снаружи** (MTProxy
   под host-сетью слушает `0.0.0.0`!):
   - Ubuntu/Debian: правило nftables (как `deploy/tproxy-firewall.service`);
   - CentOS/RHEL: `firewall-cmd` rich-rule drop на 2398/8888.
10. **Первый запуск с Let's Encrypt**:
    - генерирует самоподписанные placeholder-сертификаты в `letsencrypt/live/<домен>/`
      (иначе nginx не стартует на 443);
    - `docker compose up -d`;
    - `docker compose run --rm certbot certonly --webroot -w /var/www/certbot
      -d <домен> -m <email> --agree-tos --no-eff-email -n` (email спрашивается,
      можно пропустить с `--register-unsafely-without-email`);
    - `docker compose exec nginx nginx -s reload`;
    - healthcheck: `/healthz`, `/readyz`, `docker compose ps`.
11. **Продление сертификата**: systemd-timer `tproxy-certbot-renew.timer`
    (ежедневно): `certbot renew --webroot` + reload nginx.
12. **Итог**: печатает hostname, секрет (один раз), ссылку для клиента
    `https://t.me/webproxy?server=<домен>&secret=<секрет>` и команды проверки
    (внешние порты 2398/8888 недоступны и т.д.).

## 9. GitHub Actions (сборка образа «в GitHub» через субмодуль)

`.github/workflows/docker-image.yml`, триггеры: push в `main`, теги `v*`,
ручной запуск:

1. `actions/checkout@v4` с `submodules: recursive` — исходник релея берётся
   из субмодуля, закреплённого коммитом (воспроизводимая сборка);
2. `docker/setup-buildx-action` + `docker/login-action` (секреты
   `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`);
3. сборка и push двух образов: `tproxy:relay` и `tproxy:mtproxy`,
   теги: `latest` (main), `<sha>`, `<tag>` (для релизов).

## 10. Что НЕ меняется в tproxy-server

Ничего. Благодаря `network_mode: host` субмодуль остаётся нетронутым:
loopback-валидации, проверка peer, один XFF — всё работает как в оригинале.
Это главный довод за host-сеть (альтернатива — форк с патчем, не предлагается).

## 11. Порядок работ

1. Закоммитить и запушить `tproxy-server` (сейчас в нём 0 коммитов) →
   `github.com/<USER>/tproxy-server`.
2. Создать `tproxy-docker`, добавить субмодуль.
3. Написать оба Dockerfile + локально собрать и проверить (go test, запуск).
4. Написать `docker-compose.yml`, конфиги nginx, стартовый сайт.
5. Написать `install.sh` и проверить на чистой Ubuntu VM (и CentOS VM).
6. GitHub Actions → проверить, что образы уехали в Docker Hub.
7. README с инструкцией установки и использования.

## 12. Открытые вопросы к ревью

1. **Имена**: репозиторий `tproxy-docker`? Docker Hub репозиторий `<USER>/tproxy`
   с тегами `relay`/`mtproxy`, или два отдельных Docker Hub-репозитория?
2. **Host-сеть** — принимаете? Это единственный способ не форкать релей.
   Альтернатива: bridge-сеть + минимальный патч релея (потребует форк/поддержку
   патча при сборке).
3. **Стартовый сайт**: включаем минимальный `site/` в репозиторий? В оригинале
   сайт намеренно не поставляется (одинаковые сайты = сигнатура для active
   probing). Предлагаю включить, но явно предупредить в README заменить на свой.
4. **sslip.io** по умолчанию — ок? (альтернатива `nip.io`).
5. Поддержка CentOS: только установка Docker + firewalld, всё остальное — в
   ubuntu-образах. Ок?
6. Один образ на оба процесса (релей + MTProxy, супервизор внутри) — **не**
   рекомендую, но если хочется один образ — скажите.
