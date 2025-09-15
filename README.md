# Transcriber – Automated Audio/Video Transcription

## Overview

Transcriber is a fully automated, bash-only solution for converting audio and video files into text using OpenAI Whisper. Simply copy a media file into a designated project folder and, within minutes, a text transcript appears in a transcripts/ subfolder.

Key features:

- Simple workflow: drop files, get transcripts
- Resilient scheduling: systemd timer or cron job (default: every 10 minutes)
- Reliable state tracking: transcriptions.tsv prevents double-processing
- Robust logging: daily log rotation, error codes, and processed-file history
- Bash-only orchestration: no Python needed beyond Whisper itself

## Prerequisites

- Operating system: Linux (tested on Ubuntu 22.04 LTS and Debian 12)

- Installed packages:
  - bash 5.x or newer
  - whisper CLI (OpenAI Whisper or compatible)
  - ffmpeg (for decoding media) 
  - logrotate (typically preinstalled)
  - systemd (preferred) or cron

Check with:

```
bash --version
whisper --help
ffmpeg -version
logrotate --version
```


## Quick Installation

1. Clone or copy the project

```
sudo git clone https://github.com/sunmingtao/transcription-automation.git
cd /opt/transcriber
```

2. Run the installer
```
sudo ./scripts/install.sh
```

The installer:

- Creates a system user transcriber
- Sets up directories and permissions
- Installs logrotate configuration
- Enables a systemd timer that runs every 10 minutes (or falls back to cron if systemd isn’t present)

## Usage

1. Drop media files
   Copy any supported audio or video file (e.g. .mp3, .wav, .mp4) into:
   ```
   /opt/transcriber/project
   ```

2. Wait for processing
   Within ~10 minutes (or sooner if you manually start the service), a text transcript appears in:
   ```
   /opt/transcriber/project/transcripts
   ```
   
3. Check state & logs
- Processing state: transcriptions.tsv
- Run log: transcriber.log
- Per-file outcomes: processed.log

Example transcript path:
```
/opt/transcriber/project/transcripts/example.en.txt
```

## Managing the Service

| Action        | Command                                          |
| ------------- | ------------------------------------------------ |
| Check timer   | `systemctl status transcriber.timer`             |
| Run now       | `sudo systemctl start transcriber.service`       |
| Follow logs   | `journalctl -fu transcriber.service`             |
| Stop schedule | `sudo systemctl disable --now transcriber.timer` |
| Re-enable     | `sudo systemctl enable --now transcriber.timer`  |

If your environment uses cron instead of systemd, inspect or edit the `transcriber.cron` entry in `config/cron/`.

## Configuration

Key configuration is in `config/transcriber.env`:

| Variable        | Description                                    | Default                                          |
| --------------- | ---------------------------------------------- | ------------------------------------------------ |
| `PROJECT_DIR`   | Where to drop media files                      | `/opt/transcriber/project`                       |
| `OUTPUT_DIR`    | Where transcripts are written                  | `${PROJECT_DIR}/transcripts`                     |
| `WHISPER_MODEL` | Whisper model (e.g. `base`, `small`, `medium`) | `base`                                           |
| `EXTENSIONS`    | Space-separated list of supported extensions   | `mp3 wav m4a mp4 mov mkv webm flac ogg mpeg aac` |

After editing, reload:
```
sudo systemctl daemon-reload
sudo systemctl restart transcriber.timer
```

## File Lifecycle

1. File copied to PROJECT_DIR
2. transcriber.sh verifies file is stable (not still copying)
3. State marked in progress in transcriptions.tsv
4. Whisper creates a .txt transcript
5. State updated to complete or error
6. A line is added to processed.log for auditing

## Logs & Rotation

Logrotate keeps 7 daily compressed archives of:
- transcriber.log
- processed.log

Manual test:
```
sudo logrotate -f /etc/logrotate.conf
```

## Troubleshooting

| Issue                      | Action                                                                                        |
| -------------------------- | --------------------------------------------------------------------------------------------- |
| No new transcripts         | Check `journalctl -u transcriber.service`; verify Whisper installation                        |
| Status stuck `in progress` | Possibly crashed mid-process; inspect `transcriber.log`; edit `transcriptions.tsv` and re-run |
| Logs not rotating          | Run `sudo logrotate -f /etc/logrotate.conf`; verify `/etc/logrotate.d/transcriber` exists     |
| Disk full                  | Remove old transcripts or expand disk space                                                   |

For detailed operator steps see RUNBOOK.md

## Maintenance
- Backups: back up `transcriptions.tsv` and `transcripts/` regularly.
- Upgrades: stop timer, update scripts/configs, run `systemctl daemon-reload`, restart timer.

| Date       | Version | Author      | Notes         |
| ---------- | ------- | ----------- | ------------- |
| 2025-09-15 | 0.1     | Mingtao Sun | Initial draft |

