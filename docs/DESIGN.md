# Transcription Automation – Design Document

## 1. Overview

This project provides an automated, fault-tolerant pipeline for transcribing audio and video files using the OpenAI Whisper CLI tool.
Users simply copy supported audio/video files into a designated project folder. Every 10 minutes a scheduled job (systemd timer or cron) scans the folder, transcribes new files, and records the outcome.

Key features:

- Hands-off transcription using Whisper (`--model base` by default)
- State tracking to prevent double-processing
- Robust logging for operations and audits
- Designed to run 24/7 on Linux servers with minimal maintenance

## 2. Scope & Assumptions

### In-Scope

- Environment:

  - Ubuntu/Debian-compatible Linux distributions
  - Bash 5.x or later
  - whisper CLI and ffmpeg installed and working

- Functionality:

  - Detect newly added media files every 10 minutes
  - Generate text transcripts in .txt format
  - Maintain a state file (transcriptions.tsv) with statuses: in progress, complete, or error
  - Maintain an append-only processing log (processed.log)
  - Rotate logs daily using logrotate

- Scheduling:

  - Systemd timer (preferred) or cron job every 10 minutes

### Assumptions

- Input files fit on local disk and are not larger than what Whisper can process in available memory.
- Files are copied atomically (or at least size-stable after a few seconds).
- All paths (project directory, log locations) are writable by a dedicated transcriber system user.
- Bash is the sole orchestration language (requirement from client).
- Out of Scope (Future Enhancements)
- Speaker diarization or word-level timestamps
- Real-time streaming transcription
- Web interface or API endpoints
- Cloud/S3 integration or remote storage
- Windows or macOS deployments

### Out of Scope (Future Enhancements)

- Speaker diarization or word-level timestamps
- Real-time streaming transcription
- Web interface or API endpoints
- Cloud/S3 integration or remote storage
- Windows or macOS deployments

## 3. System Architecture
```

           ┌─────────────┐
           │ User copies │
           │ media file  │
           └──────┬──────┘
                  │
      ┌───────────▼────────────────┐
      │ Scheduled job (systemd or  │
      │ cron) every 10 minutes     │
      └──────┬─────────────────────┘
             │
    ┌────────▼─────────┐
    │ transcriber.sh   │
    └────────┬─────────┘
             │
 ┌───────────┴──────────────────────────┐
 │ 1. Detect new stable files            │
 │ 2. Mark "in progress" in TSV          │
 │ 3. Run whisper → transcripts/         │
 │ 4. Update TSV to "complete" or "error"│
 │ 5. Append outcome to processed.log    │
 └───────────────────────────────────────┘
```

#### Core components

- `transcriber.sh`: orchestrates scanning, locking, state updates, and Whisper calls.
- `transcriptions.tsv`: authoritative state file, one row per media file.
- `processed.log`: chronological processing log with timestamps and exit codes.
- `transcripts/`: output directory for Whisper .txt files.

## 4. Workflow & Data Flow

### File discovery

- find searches for files matching allowed extensions (e.g. mp3, wav, m4a, mp4, mkv).
- Skips files already marked in progress or complete.
- Checks file size twice with a delay to ensure copying is finished.

### Processing

- Once a file passes stability checks:
  - Status in transcriptions.tsv set to in progress.
  - Whisper command executed:
  `whisper "$AUDIO_FILE" --model base --output_dir transcripts --output_format txt`
  - Exit code and output path captured.
  
### Completion

- On success: status updated to complete with transcript path and exit code 0.
- On failure: status updated to error with exit code.

## 5. Error Handling & Recovery

- Locking:
  - Global lock file /tmp/transcriber_cron.lock to prevent overlapping runs.

- Idempotency:
  - Re-running the job doesn’t reprocess files with status complete or in progress.

- Crash Safety:
  - Atomic updates of transcriptions.tsv (write to temp file and mv).

- Retries:
  - Failed files stay in error until manually retried or cleaned.
  
## 6. Security & Permissions

- Runs as a dedicated non-root user transcriber.
- Project directory and logs owned by transcriber with 750 permissions.
- No network exposure; Whisper runs locally.
- Log files rotated daily to prevent growth and protect sensitive transcripts.

## 7. Deployment & Operations
  
### Installation

- install.sh script:

  - Creates transcriber user and required directories
  - Installs systemd service and timer
  - Installs logrotate config
  - Reloads systemd and starts timer
  
### Monitoring

- Logs available at:
  - `/opt/transcriber/transcriber.log` (per-run messages)
  - `/opt/transcriber/processed.log` (per-file status)

- Check status:
  ```
  systemctl status transcriber.timer
  journalctl -u transcriber.service
  ```
  
### Backups & Retention

- Back up `transcriptions.tsv` and `transcripts/` as needed.
- Logrotate keeps 7 daily rotations, compressed. 

## 8. Future Enhancements

- Notifications on completion/failure (email, Slack).
- Alternative output formats: SRT/VTT, JSON.
- Parallel processing of large backlogs.
- Integration with cloud storage (S3/GCS/Azure).
- GPU-accelerated Whisper variants.

## 9. References

- OpenAI Whisper
- Systemd Timers
- GNU Coreutils 

| Date       | Version | Author      | Notes         |
| ---------- | ------- | ----------- | ------------- |
| 2025-09-15 | 0.1     | Mingtao Sun | Initial draft |

