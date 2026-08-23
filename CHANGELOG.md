# Changelog

Все заметные изменения — в этом файле. Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

### Added

- Первый релиз: Docker-развёртывание tproxy-server (nginx → relay → MTProxy).
- `install.sh`: проверка ОС (Debian/Ubuntu, CentOS/RHEL) и x86_64, установка
  Docker, домен или `<ip>.sslip.io`, генерация конфигов, фаервол,
  Let's Encrypt с ежедневным продлением.
- Образы `ozyab/tg-proxy-relay` и `ozyab/tg-proxy-mtproto`; CI собирает их из
  тегов `v*` (версия + `latest`) и из PR/мёрджей (хэш коммита).
- Стартовый сайт `site-starter/index.html` (одна страница, без внешних
  ресурсов).

## [Unreleased]: шаблон

### Added

### Changed

### Fixed

### Security
