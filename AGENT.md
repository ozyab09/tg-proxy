# AGENT.md

Инструкции для ИИ-агентов (Codebuff и подобных), работающих с этим репозиторием.

## Что это

`tg-proxy` — Docker-развёртывание серверной части WEB-прокси Telegram
([tproxy-server](https://github.com/telegramdesktop/tproxy-server)): nginx (TLS
+ Let's Encrypt) → Go-релей → официальный MTProxy. Стек поднимается
`docker compose`, установка — `install.sh`.

Код релея живёт в **субмодуле** `tproxy-server/` (закреплённый коммит
`2873a08` репозитория `telegramdesktop/tproxy-server`). Правки в сам релей
делаются в том репозитории, не здесь.

## Раскладка

| Путь | Что это |
|---|---|
| `tproxy-server/` | субмодуль с кодом релея (не менять) |
| `Dockerfile` | образ `ozyab/tg-proxy-relay` (golang:1.26 → alpine:3.23, user tproxy/10001) |
| `mtproxy/Dockerfile` | образ `ozyab/tg-proxy-mtproto` (ubuntu:24.04, user mtproxy/10002) |
| `nginx/nginx.conf`, `nginx/tproxy.conf.tmpl` | конфиги nginx; шаблон заполняет install.sh (`__DOMAIN__`) |
| `docker-compose.yml` | 3 сервиса + certbot под профилем |
| `install.sh`, `renew-cert.sh` | установщик и продление сертификата |
| `site-starter/index.html` | стартовый сайт (одна страница, без внешних ресурсов) |
| `firewall.nft`, `deploy/tg-proxy-firewall.service` | фаервол |
| `.github/workflows/docker-image.yml` | CI: сборка и push в Docker Hub |

## Критические инварианты (не нарушать)

1. **Host-сеть обязательна.** Релей в коде отвергает запросы, чей TCP-peer не
   loopback (`server.go: clientIP()`), и принимает в конфиге только loopback
   `listen`/`admin_listen`. Поэтому все три сервиса в compose работают в
   `network_mode: host`; nginx проксирует на `127.0.0.1:8080`. Не переводить
   стек на bridge-сеть без патча релея.
2. **Единый шлюз.** nginx проксирует все пути на релей и ничего не раздаёт
   статикой. Сайт отдаёт релей из памяти (`public_dir`), файлы читаются при
   старте — после замены `site/` нужен `docker compose up -d --force-recreate relay`.
3. **Секреты и права.**
   - `config/profiles.json` — **chmod 0400, владелец uid 10001** (релей
     отклоняет файл, читаемый group/others);
   - `.env` — chmod 600 (секрет MTProxy);
   - `connection.txt` — chmod 600 (ссылка для клиентов с секретом);
   - секрет передаётся MTProxy аргументом `-S` (виден в процессе — не давать
     посторонним доступ к хосту).
4. **Логирование.** Никогда не включать логирование URI/заголовков на nginx и
   релее: в query моста живёт capability, в заголовках WebSocket — bearer.
   `access_log off` в `nginx/nginx.conf` обязателен.
5. **Требования релея к nginx**: `Host $host` (релей сверяет Host с
   `public_hostname`), ровно один `X-Forwarded-For` (`$remote_addr`),
   `client_max_body_size 2m` (лимит релея 2 MiB), `proxy_read_timeout 40s`
   (> long-poll 25s), WebSocket-заголовки (`Upgrade`/`Connection`), без
   буферизации.
6. **MTProxy слушает `0.0.0.0:2398`** (нет опции bind) — фаервол обязан
   закрывать 2398/8888 на не-loopback интерфейсах (`firewall.nft`). Статы
   `8888` по документации MTProxy — только loopback.
7. **CSP публичного сайта**: релей отдаёт страницы с `style-src 'self'` —
   inline `<style>`/`<script>` в `site/` блокируются. Стартовый сайт использует
   семантический HTML + inline SVG с presentation-атрибутами.
8. **MTProxy — только x86_64.** install.sh проверяет `uname -m`.

## Сборка и проверка

```bash
# релей (субмодуль)
cd tproxy-server && go build ./... && go vet ./... && go test ./...

# образы (BuildKit)
docker build -t tg-proxy-relay:test .
docker build -t tg-proxy-mtproto:test mtproxy/

# синтаксис скриптов
bash -n install.sh renew-cert.sh

# конфиги
ruby -e "require 'yaml'; YAML.load_file('docker-compose.yml')"
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/docker-image.yml')"
```

Smoke-тест релея: собрать тестовый `config.json`/`profiles.json`
(`public_hostname` = тестовый домен, `profiles.json` chmod 600), запустить
`docker run --rm -u 0 -v ... tg-proxy-relay:test`, проверить внутри контейнера
через `docker exec`: `/healthz` на 8081, сайт и мост на 8080 с заголовком
`Host: <тестовый домен>` (без корректного Host релей вернёт 404). Порт не
пробрасывается, т.к. релей слушает `127.0.0.1` внутри контейнера — проверять
только через `docker exec`.

## Политика версий (CI)

Workflow в `.github/workflows/docker-image.yml`:

- PR / push в `main` → образы с тегом `<sha12>` (dev);
- тег `v*` → `<версия>` + `latest` (latest двигается только релизом);
- образы: `ozyab/tg-proxy-relay`, `ozyab/tg-proxy-mtproto`;
- секреты CI: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.

Workflow в `.github/workflows/release.yml` — автоматический релиз через
[cocogitto](https://docs.cocogitto.io) при пуше в `main`:

- ковыряет коммиты после последнего тега, определяет bump по conventional
  commits (`feat:` → minor, `fix:` → patch, `feat!:` → major);
- создаёт тег `v*`, коммит с `CHANGELOG.md` и GitHub Release;
- тег `v*` запускает `docker-image.yml`, который собирает релизные образы.

Конфигурация cocogitto: `cog.toml`. Если квалифицирующих коммитов нет —
выход чистый, без создания тега.

**Важно:** тег пушится через `PAT_TOKEN` (Personal Access Token с scope
`repo`), иначе `docker-image.yml` не триггерится (ограничение `GITHUB_TOKEN`).
Секрет `PAT_TOKEN` должен быть настроен в Settings → Secrets → Actions.

Новую версию релея подхватывают обновлением субмодуля: `git -C tproxy-server
fetch && git -C tproxy-server checkout <commit>` в корне — CI соберёт из него.

## Обновление версий базовых образов

При апгрейде `golang:`/`alpine:`/`ubuntu:`/`nginx:`/Actions-версий проверять
существование тегов (Docker Hub API `https://hub.docker.com/v2/repositories/
<repo>/tags/<tag>`), пересобирать оба образа локально и прогонять smoke-тест.
Для ubuntu 24.04 пакет OpenSSL называется `libssl3t64` (не `libssl3`).
