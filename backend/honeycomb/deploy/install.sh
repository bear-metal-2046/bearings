#!/usr/bin/env bash
set -euo pipefail

fail() { printf '%s\n' "$*" >&2; exit 1; }

bundle=${1:-}
domain=${2:-}
[[ $# -ge 1 && $# -le 2 ]] || fail 'Usage: sudo bash install.sh BUNDLE_DIR [PUBLIC_HOSTNAME]'
[[ $(id -u) == 0 ]] || fail 'Run this installer with sudo on the Honeycomb VM.'
[[ -x "$bundle/bin/server" && -f "$bundle/lib/libdartaotserver.so" ]] ||
  fail "Expected the compiled Linux bundle (bin/server and lib/) in $bundle."
if [[ -n $domain && ! $domain =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
  fail 'Pass a public hostname without https://, a port, or a path.'
fi

umask 022
base=/opt/honeycomb
current=$base/current
env_file=/etc/honeycomb.env
exec 9>/run/lock/honeycomb-deploy.lock
flock -n 9 || fail 'Another Honeycomb install is running.'

if [[ ! -e $env_file ]]; then
  install -m 600 /dev/null "$env_file"
  cat > "$env_file" <<'ENV'
AUTH0_ISSUER=
AUTH0_AUDIENCE=
HONEYCOMB_BOOTSTRAP_SUBJECT=
HONEYCOMB_DATABASE=/var/lib/honeycomb/honeycomb.sqlite

# Set the credentials for any integrations you use.
# TBA_API_KEY=
# NEXUS_API_KEY=
# NEXUS_WEBHOOK_TOKEN=
# AUTH0_MANAGEMENT_CLIENT_ID=
# AUTH0_MANAGEMENT_CLIENT_SECRET=
# AUTH0_WEBHOOK_TOKEN=
# BEARIMETRIC_AUTH0_CLIENT_ID=
# BEARIMETRIC_AUTH0_CLIENT_SECRET=
ENV
  if [[ -n $domain ]]; then
    printf 'HONEYCOMB_PUBLIC_API_URL=https://%s/api/\n' "$domain" >> "$env_file"
  else
    printf '# HONEYCOMB_PUBLIC_API_URL=https://your-hostname/api/\n' >> "$env_file"
  fi
fi

has_auth_config() {
  grep -Eq '^AUTH0_ISSUER=.+$' "$env_file" && grep -Eq '^AUTH0_AUDIENCE=.+$' "$env_file"
}

if ! has_auth_config; then
  printf 'Enter AUTH0_ISSUER, AUTH0_AUDIENCE and your bootstrap Auth0 subject in %s.\n' "$env_file"
  if [[ -t 0 ]]; then
    editor=${EDITOR:-nano}
    command -v "$editor" >/dev/null || editor=vi
    "$editor" "$env_file"
  fi
  has_auth_config || fail "Fill in $env_file with sudoedit, then run the install again."
fi

packages=()
command -v curl >/dev/null || packages+=(curl)
command -v sqlite3 >/dev/null || packages+=(sqlite3)
if [[ -n $domain ]] && ! command -v caddy >/dev/null; then
  packages+=(caddy)
fi
if (( ${#packages[@]} )); then
  apt-get update
  apt-get install -y "${packages[@]}"
fi

if ! id honeycomb >/dev/null 2>&1; then
  useradd --system --user-group --home-dir /var/lib/honeycomb --shell /usr/sbin/nologin honeycomb
fi
install -d -m 755 "$base/releases"

cat > /etc/systemd/system/honeycomb.service <<'UNIT'
[Unit]
Description=Honeycomb Grove server
After=network-online.target
Wants=network-online.target

[Service]
User=honeycomb
Group=honeycomb
StateDirectory=honeycomb
StateDirectoryMode=0750
WorkingDirectory=/var/lib/honeycomb
Environment=PORT=8080
EnvironmentFile=/etc/honeycomb.env
ExecStart=/opt/honeycomb/current/bin/server
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

if [[ -n $domain ]]; then
  caddyfile=/etc/caddy/Caddyfile
  fragment=/etc/caddy/honeycomb.caddy
  backup=$(mktemp -d)
  cp "$caddyfile" "$backup/Caddyfile"
  if [[ -f $fragment ]]; then cp "$fragment" "$backup/honeycomb.caddy"; fi
  printf '%s {\n    reverse_proxy 127.0.0.1:8080\n}\n' "$domain" > "$fragment"
  if ! grep -Fxq 'import /etc/caddy/honeycomb.caddy' "$caddyfile"; then
    printf '\nimport /etc/caddy/honeycomb.caddy\n' >> "$caddyfile"
  fi
  if ! caddy validate --config "$caddyfile" --adapter caddyfile; then
    cp "$backup/Caddyfile" "$caddyfile"
    if [[ -f $backup/honeycomb.caddy ]]; then
      cp "$backup/honeycomb.caddy" "$fragment"
    else
      rm -f "$fragment"
    fi
    rm -r "$backup"
    fail 'Caddy configuration failed validation. The previous configuration was restored.'
  fi
  rm -r "$backup"
  systemctl enable --now caddy
  systemctl reload caddy
fi

release=$(mktemp -d "$base/releases/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
cp -R -- "$bundle/." "$release/"
chmod -R a+rX,go-w "$release"
previous=$(readlink "$current" || true)

activate() {
  ln -sfnT "$1" "$base/.next"
  mv -Tf "$base/.next" "$current"
}

grove_ready() {
  local status
  for (( attempt=0; attempt<20; attempt++ )); do
    status=$(curl --silent --noproxy '*' --http1.1 --max-time 1 --output /dev/null --write-out '%{http_code}' \
      -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
      -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: MDEyMzQ1Njc4OWFiY2RlZg==' \
      http://127.0.0.1:8080/api/grove/ws || true)
    if [[ $status == 101 ]]; then return 0; fi
    sleep 1
  done
  return 1
}

systemctl daemon-reload
activate "$release"
if systemctl restart honeycomb && grove_ready; then
  systemctl enable honeycomb
  printf 'Honeycomb is running from %s.\n' "$release"
  if [[ -n $domain ]]; then printf 'Public URL: https://%s\n' "$domain"; fi
else
  journalctl -u honeycomb -n 20 --no-pager >&2 || true
  if [[ -n $previous ]]; then
    activate "$previous"
    systemctl restart honeycomb
    fail "The new release failed its Grove check. Restarted $previous."
  fi
  systemctl stop honeycomb || true
  rm -f "$current"
  fail "Honeycomb failed its Grove check. Review $env_file and run the install again."
fi
