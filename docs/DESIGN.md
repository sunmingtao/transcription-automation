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
