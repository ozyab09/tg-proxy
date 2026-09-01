#!/usr/bin/env bash
#
# tg-proxy installer — Ubuntu/Debian and CentOS/RHEL (x86_64).
#
#   curl -fsSL https://raw.githubusercontent.com/ozyab09/tg-proxy/main/install.sh | sudo bash
#
# What it does:
#   1. checks root, x86_64, free ports 80/443 and the distribution;
#   2. installs Docker + Compose plugin;
#   3. asks for a domain (default: <public-ip>.sslip.io) and an MTProxy secret;
#   4. downloads the repository (with the tproxy-server submodule) to /opt/tg-proxy;
#   5. writes .env, config/config.json, config/profiles.json, nginx/tproxy.conf;
#   6. downloads the official MTProxy secret and routing config;
#   7. configures the firewall (allow 80/443, block 2398/8888 externally);
#   8. boots the stack, obtains a Let's Encrypt certificate and installs a
#      daily renewal timer.
#
# Re-running is safe: the existing domain, secret, site and certificate are
# kept.

set -euo pipefail

REPO_URL="https://github.com/ozyab09/tg-proxy.git"
INSTALL_DIR="/opt/tg-proxy"
RELAY_UID="10001"   # matches USER in the relay Dockerfile

DOMAIN=""
SECRET=""
EMAIL=""
PUBLIC_IP=""
DISTRO=""
COMPOSE=()

log()  { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

require_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "Run as root: sudo bash install.sh"
}

check_arch() {
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *) fail "Official MTProxy supports x86_64 only (this host: $(uname -m))." ;;
  esac
}

detect_distro() {
  if command -v apt-get >/dev/null 2>&1; then
    DISTRO="debian"
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    DISTRO="redhat"
  else
    fail "Unsupported distribution: need apt (Debian/Ubuntu) or dnf/yum (CentOS/RHEL)."
  fi
  log "Detected distribution: $DISTRO"
}

check_ports() {
  for port in 80 443; do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      fail "Port $port is already in use. Free it before installing."
    fi
  done
}

ensure_prereqs() {
  if ! command -v curl >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
    log "Installing curl and openssl"
    if [[ "$DISTRO" == "debian" ]]; then
      apt-get update -qq
      apt-get install -y -qq --no-install-recommends curl openssl ca-certificates
    else
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y curl openssl ca-certificates
      else
        yum install -y curl openssl ca-certificates
      fi
    fi
  fi
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker (get.docker.com)"
    curl -fsSL https://get.docker.com | sh
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    log "Docker Compose plugin is missing — installing docker-compose-plugin"
    if [[ "$DISTRO" == "debian" ]]; then
      # shellcheck disable=SC2015
      apt-get update -qq && apt-get install -y -qq docker-compose-plugin || true
    else
      dnf install -y docker-compose-plugin 2>/dev/null \
        || yum install -y docker-compose-plugin || true
    fi
    if ! docker compose version >/dev/null 2>&1; then
      # The package is unavailable (e.g. Docker installed from distro repos or
      # a snap): install the standalone compose binary as a CLI plugin.
      log "Package not available — installing standalone docker compose binary"
      local dir="/usr/local/lib/docker/cli-plugins"
      local version=""
      mkdir -p "$dir"
      version="$(curl -fsSL --max-time 20 https://api.github.com/repos/docker/compose/releases/latest \
        | sed -n 's/.*"tag_name": *"\(v[^"]*\)".*/\1/p' | head -1)"
      [[ -n "$version" ]] || fail "Could not determine the latest docker compose version."
      curl -fsSL --max-time 120 \
        "https://github.com/docker/compose/releases/download/${version}/docker-compose-linux-$(uname -m)" \
        -o "$dir/docker-compose"
      chmod +x "$dir/docker-compose"
    fi
    docker compose version >/dev/null 2>&1 \
      || fail "Docker Compose is still unavailable after installation."
    COMPOSE=(docker compose)
  fi
  log "Docker $(docker --version | awk '{print $3}')"
}

ask_domain() {
  PUBLIC_IP="$(curl -fsSL --max-time 10 https://api.ipify.org 2>/dev/null \
    || curl -fsSL --max-time 10 https://ifconfig.me/ip 2>/dev/null || true)"
  [[ -n "$PUBLIC_IP" ]] || warn "Could not detect the public IP automatically."
  local default_domain=""
  [[ -n "$PUBLIC_IP" ]] && default_domain="${PUBLIC_IP}.sslip.io"
  read -r -p "Domain name (Enter for ${default_domain:-<public-ip>.sslip.io}): " DOMAIN
  DOMAIN="${DOMAIN:-$default_domain}"
  [[ -n "$DOMAIN" ]] || fail "No domain given."
  DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
  [[ "$DOMAIN" =~ ^[a-z0-9.-]+$ ]] || fail "Invalid domain: $DOMAIN"
  if [[ -n "$PUBLIC_IP" ]]; then
    local resolved
    resolved="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')"
    if [[ -n "$resolved" && "$resolved" != "$PUBLIC_IP" ]]; then
      warn "$DOMAIN resolves to $resolved but the detected public IP is $PUBLIC_IP."
      warn "Certificate issuance will fail until DNS points at this server."
    fi
  fi
  log "Domain: $DOMAIN"
}

ask_secret() {
  read -r -s -p "MTProxy secret (32 hex chars) — empty to generate: " SECRET
  echo
  if [[ -z "$SECRET" ]]; then
    SECRET="$(openssl rand -hex 16)"
    log "Generated secret: $SECRET   (shown once — save it)"
  fi
  SECRET="$(printf '%s' "$SECRET" | tr '[:upper:]' '[:lower:]')"
  [[ "$SECRET" =~ ^[0-9a-f]{32}$ ]] || fail "Secret must be 32 hexadecimal characters."
}

ask_email() {
  read -r -p "Let's Encrypt contact email (Enter to skip): " EMAIL
}

clone_repo() {
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Updating $INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null || warn "git pull failed; continuing with existing files."
  elif [[ -e "$INSTALL_DIR" ]]; then
    fail "$INSTALL_DIR exists but is not a git checkout; remove it first."
  else
    log "Downloading tg-proxy to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    git clone --recursive "$REPO_URL" "$INSTALL_DIR"
  fi
  cd "$INSTALL_DIR"
}

reuse_or_ask() {
  # Domain: reuse config.json when present (safe re-run).
  if [[ -f config/config.json ]] && grep -q '"public_hostname"' config/config.json; then
    DOMAIN="$(sed -n 's/.*"public_hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' config/config.json)"
    log "Reusing domain from config/config.json: $DOMAIN"
  else
    ask_domain
  fi
  # Secret: reuse .env when present (safe re-run).
  if [[ -f .env ]] && grep -q '^MTPROXY_SECRET=' .env; then
    SECRET="$(sed -n 's/^MTPROXY_SECRET=//p' .env)"
    log "Reusing existing MTProxy secret from .env (delete .env to rotate)."
  else
    ask_secret
  fi
  ask_email
}

generate_configs() {
  mkdir -p config nginx site mtproxy-data letsencrypt certbot-webroot

  umask 077
  log "Writing .env (chmod 600)"
  printf 'MTPROXY_SECRET=%s\n' "$SECRET" > .env
  chmod 600 .env

  log "Writing connection.txt (chmod 600)"
  cat > connection.txt <<EOF
Hostname: $DOMAIN
Secret:   $SECRET

Telegram WEB proxy link for clients:
  https://t.me/webproxy?server=$DOMAIN&secret=$SECRET
EOF
  chmod 600 connection.txt

  log "Writing config/config.json and config/profiles.json (chmod 0400)"
  cat > config/config.json <<EOF
{
  "public_hostname": "$DOMAIN",
  "listen": "127.0.0.1:8080",
  "admin_listen": "127.0.0.1:8081",
  "public_dir": "/srv/tproxy-site",
  "profiles_file": "/etc/tproxy/profiles.json",
  "enable_pprof": false,
  "limits": {
    "max_header_bytes": 16384,
    "max_body_bytes": 2097152,
    "max_frame_payload": 1048576,
    "carrier_batch_bytes": 2097152,
    "max_streams_per_session": 128,
    "max_closed_stream_ids": 4096,
    "max_pending_per_session": 33554432,
    "max_pending_global": 536870912,
    "max_pending_items_per_session": 16384,
    "max_pending_items_global": 262144,
    "max_sessions_per_ip": 0,
    "max_sessions_global": 128,
    "max_streams_global": 4096,
    "max_backend_dials_in_flight": 256,
    "new_sessions_per_minute": 600,
    "new_sessions_burst": 128,
    "new_streams_per_minute": 6000,
    "new_streams_burst": 512,
    "max_bootstraps_per_ip": 0,
    "max_bootstraps_global": 512,
    "new_bootstraps_per_minute": 1200,
    "new_bootstraps_burst": 256,
    "max_profiles": 32
  },
  "timeouts": {
    "backend_dial": "5s",
    "long_poll": "25s",
    "reconnect_grace": "2m",
    "bootstrap_lifetime": "2m",
    "read_header": "10s",
    "idle": "75s",
    "shutdown": "15s"
  }
}
EOF
  cat > config/profiles.json <<EOF
{
  "profiles": [
    {
      "name": "default",
      "secret": "$SECRET",
      "backend": "127.0.0.1:2398",
      "carrier_mode": "https"
    }
  ]
}
EOF
  chmod 0400 config/config.json config/profiles.json
  chown "$RELAY_UID:$RELAY_UID" config/config.json config/profiles.json

  log "Rendering nginx/tproxy.conf from the template"
  sed "s/__DOMAIN__/$DOMAIN/g" nginx/tproxy.conf.tmpl > nginx/tproxy.conf
  chmod 0644 nginx/tproxy.conf

  umask 022
  if [[ ! -f site/index.html ]]; then
    log "Installing the starter site (replace site/index.html with your own)"
    cp site-starter/index.html site/index.html
    chmod 0644 site/index.html
  fi
}

mtproxy_data() {
  log "Downloading Telegram MTProxy secret and routing config"
  curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
    -o mtproxy-data/proxy-secret https://core.telegram.org/getProxySecret
  curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
    -o mtproxy-data/proxy-multi.conf https://core.telegram.org/getProxyConfig
  chmod 0644 mtproxy-data/proxy-secret mtproxy-data/proxy-multi.conf
  test -s mtproxy-data/proxy-secret
  grep -q '^default ' mtproxy-data/proxy-multi.conf
}

configure_firewall() {
  log "Configuring firewall: allow 80/443, block 2398/8888 externally"
  if [[ "$DISTRO" == "debian" ]]; then
    if ! command -v nft >/dev/null 2>&1; then
      apt-get update -qq
      apt-get install -y -qq --no-install-recommends nftables
    fi
    mkdir -p /etc/tproxy-server
    install -m 0644 firewall.nft /etc/tproxy-server/firewall.nft
    install -m 0644 deploy/tg-proxy-firewall.service /etc/systemd/system/tg-proxy-firewall.service
    systemctl daemon-reload
    systemctl enable --now tg-proxy-firewall.service >/dev/null 2>&1 \
      || warn "Could not enable tg-proxy-firewall.service (is nftables present?)."
  else
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
      firewall-cmd --permanent --add-service=http >/dev/null
      firewall-cmd --permanent --add-service=https >/dev/null
      firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=2398 protocol=tcp drop' >/dev/null
      firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=8888 protocol=tcp drop' >/dev/null
      firewall-cmd --reload >/dev/null
      log "firewalld: http/https allowed, 2398/8888 dropped"
    else
      warn "firewalld not active or missing. Open TCP 80/443 and block 2398/8888 manually."
    fi
  fi
}

cert_is_live() {
  [[ -f "letsencrypt/live/$DOMAIN/fullchain.pem" ]] \
    && openssl x509 -in "letsencrypt/live/$DOMAIN/fullchain.pem" -noout -issuer 2>/dev/null \
       | grep -qi "lets encrypt"
}

obtain_certificate() {
  if cert_is_live; then
    log "Certificate for $DOMAIN already exists; skipping issuance"
    return 0
  fi

  log "Creating a placeholder certificate so nginx can boot"
  mkdir -p "letsencrypt/live/$DOMAIN"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "letsencrypt/live/$DOMAIN/privkey.pem" \
    -out "letsencrypt/live/$DOMAIN/fullchain.pem" \
    -subj "/CN=$DOMAIN" >/dev/null 2>&1

  log "Starting services (${COMPOSE[*]} up -d)"
  "${COMPOSE[@]}" up -d

  for _ in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8081/healthz >/dev/null 2>&1; then break; fi
    sleep 1
  done
  curl -fsS http://127.0.0.1:8081/healthz >/dev/null 2>&1 \
    || warn "Relay health endpoint not responding yet; continuing."

  log "Requesting a Let's Encrypt certificate for $DOMAIN"
  # Drop stale empty renewal configs left by failed attempts; otherwise
  # `certbot renew` trips over an unparsable file every day.
  find "letsencrypt/renewal" -maxdepth 1 -type f -name "${DOMAIN}*.conf" -size -20c -delete 2>/dev/null || true
  # The placeholder is deliberately NOT removed first: if issuance fails,
  # nginx still has a cert to load and stays up instead of crash-looping.
  # --force-renewal makes certbot replace the self-signed placeholder in place.
  local args=(certonly --webroot -w /var/www/certbot -d "$DOMAIN" --force-renewal --agree-tos --no-eff-email -n)
  if [[ -n "$EMAIL" ]]; then
    "${COMPOSE[@]}" --profile certbot run --rm certbot "${args[@]}" -m "$EMAIL"
  else
    "${COMPOSE[@]}" --profile certbot run --rm certbot "${args[@]}" --register-unsafely-without-email
  fi
  # If live/$DOMAIN already held the placeholder, certbot issues into a
  # suffixed directory (live/$DOMAIN-0001). Point the canonical path at the
  # issued certificate so nginx serves the real cert.
  if ! openssl x509 -in "letsencrypt/live/$DOMAIN/fullchain.pem" -noout -issuer 2>/dev/null | grep -qi "lets encrypt"; then
    local issued="" candidate="" base=""
    for candidate in "letsencrypt/live/${DOMAIN}-"*; do
      if [[ -e "$candidate/fullchain.pem" ]] \
        && openssl x509 -in "$candidate/fullchain.pem" -noout -issuer 2>/dev/null | grep -qi "lets encrypt"; then
        issued="$candidate"
        break
      fi
    done
    if [[ -n "$issued" ]]; then
      base="$(basename "$issued")"
      rm -f "letsencrypt/live/$DOMAIN/fullchain.pem" "letsencrypt/live/$DOMAIN/privkey.pem"
      ln -s "../${base}/fullchain.pem" "letsencrypt/live/$DOMAIN/fullchain.pem"
      ln -s "../${base}/privkey.pem" "letsencrypt/live/$DOMAIN/privkey.pem"
      log "Linked issued certificate from live/${base}"
    else
      warn "Issuance did not produce a Let's Encrypt certificate; keeping the placeholder."
    fi
  fi
  "${COMPOSE[@]}" exec nginx nginx -s reload
  log "Certificate issued"
}

install_renewal_timer() {
  log "Installing the daily certificate renewal timer"
  install -m 0755 renew-cert.sh /usr/local/bin/tg-proxy-renew-cert.sh
  cat > /etc/systemd/system/tg-proxy-certbot.service <<EOF
[Unit]
Description=Renew Let's Encrypt certificates for tg-proxy
After=docker.service network-online.target

[Service]
Type=oneshot
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/tg-proxy-renew-cert.sh
EOF
  cat > /etc/systemd/system/tg-proxy-certbot.timer <<EOF
[Unit]
Description=Daily Let's Encrypt certificate renewal for tg-proxy

[Timer]
OnCalendar=*-*-* 03:17:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now tg-proxy-certbot.timer
}

verify() {
  log "Stack status:"
  "${COMPOSE[@]}" ps
  log "Relay health: $(curl -fsS http://127.0.0.1:8081/healthz 2>/dev/null || echo FAIL)"
  log "Relay ready:  $(curl -fsS http://127.0.0.1:8081/readyz 2>/dev/null || echo FAIL)"
  log "Site over HTTPS: $(curl -fsS -o /dev/null -w '%{http_code}' --max-time 15 "https://$DOMAIN/" 2>/dev/null || echo FAIL)"
}

summary() {
  cat <<EOF

============================================================
  tg-proxy is installed.

  Hostname: $DOMAIN
  Secret:   $SECRET   (also in $INSTALL_DIR/.env, chmod 600)

  Telegram WEB proxy link for clients:
    https://t.me/webproxy?server=$DOMAIN&secret=$SECRET
    (also saved to $INSTALL_DIR/connection.txt, chmod 600)

  Files:      $INSTALL_DIR
  Re-run:     cd $INSTALL_DIR && sudo ./install.sh
  Site:       replace $INSTALL_DIR/site/index.html, then:
                cd $INSTALL_DIR && docker compose up -d --force-recreate relay
  Renewal:    systemd timer tg-proxy-certbot.timer (daily)
  Firewall:   TCP 80/443 open; 2398/8888 blocked externally.
              Keep the provider firewall as the first boundary.
  Logs:       journalctl -u docker; cd $INSTALL_DIR && docker compose logs -f
============================================================
EOF
}

main() {
  require_root
  # When run as `curl ... | sudo bash`, stdin is the script itself, so the
  # interactive prompts below would read the remaining script instead of the
  # terminal. Restore the controlling terminal for user input.
  if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
    exec </dev/tty
  fi
  check_arch
  detect_distro
  check_ports
  ensure_prereqs
  install_docker
  clone_repo
  reuse_or_ask
  generate_configs
  mtproxy_data
  configure_firewall
  obtain_certificate
  install_renewal_timer
  verify
  summary
}

main "$@"
