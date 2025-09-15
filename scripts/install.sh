#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/transcriber"
sudo useradd -r -s /usr/sbin/nologin transcriber 2>/dev/null || true
sudo mkdir -p "$BASE"/{scripts,config,docs,samples}
sudo cp -r ./scripts ./config ./docs ./samples "$BASE"/
sudo chown -R transcriber:transcriber "$BASE"
sudo chmod -R 750 "$BASE"

# log files & project dir
source "$BASE/config/transcriber.env"
sudo mkdir -p "$PROJECT_DIR" "$(dirname "$RUN_LOG")" "$(dirname "$PROCESSED_LOG")" "$OUTPUT_DIR"
sudo touch "$STATE_FILE" "$RUN_LOG" "$PROCESSED_LOG"
sudo chown -R transcriber:transcriber "$PROJECT_DIR"
sudo chown transcriber:transcriber "$STATE_FILE" "$RUN_LOG" "$PROCESSED_LOG"

# logrotate
sudo cp "$BASE/config/logrotate-transcriber" /etc/logrotate.d/transcriber

# systemd
if command -v systemctl >/dev/null 2>&1; then
  sudo cp "$BASE/config/systemd/transcriber.service" /etc/systemd/system/
  sudo cp "$BASE/config/systemd/transcriber.timer"   /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now transcriber.timer
  echo "Installed with systemd timer (every 10 minutes)."
else
  # fallback to cron
  (crontab -u transcriber -l 2>/dev/null; echo "$(cat $BASE/config/cron/transcriber.cron)") | sudo crontab -u transcriber -
  echo "Installed with cron."
fi

echo "✅ Installation complete. Drop media files into: $PROJECT_DIR"

