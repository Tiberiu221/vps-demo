#!/usr/bin/env bash
# Redeploy vps-demo. Run on the server as user 'app':  bash ~/vps-demo/deploy/deploy.sh
set -euo pipefail

SERVICE=vps-demo
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3000/health}"

cd "$(dirname "$0")/.."   # repo root, wherever the script is called from

echo "==> [1/4] git pull"
if [ -d .git ]; then
  git pull --ff-only
else
  echo "    not a git checkout (files copied with scp), skipping"
fi

echo "==> [2/4] npm ci --omit=dev"
npm ci --omit=dev

echo "==> [3/4] sudo systemctl restart $SERVICE"
sudo systemctl restart "$SERVICE"

echo "==> [4/4] health check $HEALTH_URL"
# Give node a second to start listening, retry a few times if it is slow; print the logs either way.
sleep 1
status=0
if curl -fsS --retry 5 --retry-delay 1 --retry-connrefused "$HEALTH_URL"; then
  echo
  echo "==> Deploy OK"
else
  echo "==> Deploy FAILED: health check did not pass" >&2
  status=1
fi

echo "==> Last 20 log lines"
journalctl -u "$SERVICE" -n 20 --no-pager
exit "$status"
