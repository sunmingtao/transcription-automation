#!/usr/bin/env bash
set -euo pipefail

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl disable --now transcriber.timer || true
  sudo rm -f /etc/systemd/system/transcriber.timer /etc/systemd/system/transcriber.service
  sudo systemctl daemon-reload || true
else
  sudo crontab -u transcriber -l 2>/dev/null | grep -v 'transcriber.sh' | sudo crontab -u transcriber - || true
fi

sudo rm -f /etc/logrotate.d/transcriber

echo "Removed scheduler and logrotate. Data left in /opt/transcriber. Use --purge to delete."

