#!/usr/bin/env bash
# One-time bootstrap for a fresh Ubuntu 24.04 server. Run as root:  bash setup-server.sh
# Idempotent: re-running it leaves the server in the same state (never overwrites app.env).
set -euo pipefail

APP_USER=app
SERVICE=vps-demo
ENV_FILE=/etc/vps-demo/app.env

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root (or with sudo)." >&2
  exit 1
fi

# No interactive dialogs from apt/needrestart while installing.
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

echo "==> [1/6] User '$APP_USER' (SSH key login only, no password)"
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$APP_USER"
fi
usermod -aG systemd-journal "$APP_USER"   # lets 'app' read logs with journalctl
install -d -m 700 -o "$APP_USER" -g "$APP_USER" "/home/$APP_USER/.ssh"
if [ -s /root/.ssh/authorized_keys ]; then
  install -m 600 -o "$APP_USER" -g "$APP_USER" /root/.ssh/authorized_keys "/home/$APP_USER/.ssh/authorized_keys"
else
  echo "    WARNING: /root/.ssh/authorized_keys missing, 'ssh $APP_USER@server' will not work" >&2
fi

echo "==> [2/6] sudo for '$APP_USER': only 'systemctl restart $SERVICE', no password"
sudoers_tmp=$(mktemp)
echo "$APP_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart $SERVICE" > "$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null   # validate first: a broken sudoers file breaks sudo
install -m 440 "$sudoers_tmp" "/etc/sudoers.d/$SERVICE"
rm -f "$sudoers_tmp"

echo "==> [3/6] Packages: nginx, git, curl, ufw"
# Fresh cloud servers often run Ubuntu's automatic updates right after first boot: wait, or apt fails on its lock.
while [[ "$(systemctl is-active apt-daily.service apt-daily-upgrade.service)" == *activating* ]]; do
  echo "    waiting for automatic apt updates to finish..."
  sleep 5
done
apt-get update
apt-get install -y ca-certificates curl git nginx ufw

echo "==> [4/6] Node.js 22 from NodeSource"
if ! node --version 2>/dev/null | grep -q '^v22\.'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
  bash /tmp/nodesource_setup.sh
  apt-get install -y nodejs
fi

echo "==> [5/6] Firewall (ufw): SSH, HTTP, HTTPS"
ufw allow OpenSSH   # before 'enable', so we never lock ourselves out
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> [6/6] Env file $ENV_FILE (root-only, read by systemd)"
install -d -m 755 "$(dirname "$ENV_FILE")"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'EOF'
# vps-demo runtime config, loaded by systemd (EnvironmentFile=). KEY=value, no quotes/export.
NODE_ENV=production
# Keep 3000: nginx and deploy.sh point to 127.0.0.1:3000
PORT=3000
APP_NAME=change-me
EOF
fi
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo
echo "==> Done"
echo "node $(node --version), npm $(npm --version), $(nginx -v 2>&1)"
ls -l "$ENV_FILE"
ufw status
