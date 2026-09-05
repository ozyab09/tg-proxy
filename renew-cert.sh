#!/usr/bin/env bash
set -euo pipefail

# Run from the compose directory. When installed (install.sh copies this to
# /usr/local/bin and systemd sets WorkingDirectory=$INSTALL_DIR), $PWD is
# already the right directory — but `docker compose` must find docker-compose.yml,
# so never trust $(dirname "$0") (that is /usr/local/bin when installed).
if [[ -n "${TG_PROXY_DIR:-}" ]]; then
  cd "$TG_PROXY_DIR"
elif [[ -f docker-compose.yml ]]; then
  : # already in the compose directory
else
  echo "renew-cert.sh: cannot locate docker-compose.yml (TG_PROXY_DIR not set)" >&2
  exit 1
fi

docker compose --profile certbot run --rm certbot renew --webroot -w /var/www/certbot --quiet
docker compose exec nginx nginx -s reload || true
