# RUNBOOK – Transcriber Service

This runbook is the operational guide for installing, running, monitoring, and troubleshooting the Transcriber automation.
The service watches a project directory for new audio/video files and uses Whisper to create text transcripts automatically.

## 1. Overview

**Service** name: `transcriber`

**Purpose:**

- Detect new audio/video files in a project folder.
- Transcribe them to .txt files using Whisper.
- Maintain state and logs for auditing and troubleshooting.

**Core files and directories** (default paths):

| Item                             | Path                                          |
| -------------------------------- | --------------------------------------------- |
| Project folder (drop media here) | `/opt/transcriber/project`                    |
| Transcripts output               | `/opt/transcriber/project/transcripts`        |
| State file                       | `/opt/transcriber/project/transcriptions.tsv` |
| Per-run log                      | `/opt/transcriber/project/transcriber.log`    |
| Processed file log               | `/opt/transcriber/project/processed.log`      |
| Main script                      | `/opt/transcriber/scripts/transcriber.sh`     |
| Systemd unit                     | `/etc/systemd/system/transcriber.service`     |
| Systemd timer                    | `/etc/systemd/system/transcriber.timer`       |
| Logrotate config                 | `/etc/logrotate.d/transcriber`                |


## 2. Daily Operations

### Check that the service is running

`systemctl status transcriber.timer`

Look for:

- Active: active (waiting) → the timer is loaded and will trigger the service.
- Next scheduled run time.

To see the most recent run of the job:

`journalctl -u transcriber.service --since "1 hour ago"`

### View current logs

```
less /opt/transcriber/project/transcriber.log
less /opt/transcriber/project/processed.log
```

`transcriber.log` contains run-by-run operational messages.
`processed.log` is an append-only TSV with the outcome (complete/error) for each file.

### Drop a new file to process

Copy or move an audio/video file into `/opt/transcriber/project`.
Within ~10 minutes (or sooner if triggered manually), a transcript will appear in the transcripts subfolder.

## 3. Manual Operations

| Action                                    | Command                                     |
| ----------------------------------------- | ------------------------------------------- |
| Run immediately                           | `systemctl start transcriber.service`       |
| Stop future runs (keep service installed) | `systemctl disable --now transcriber.timer` |
| Resume scheduled runs                     | `systemctl enable --now transcriber.timer`  |
| Tail logs live                            | `journalctl -fu transcriber.service`        |

## 4. File Processing States

Each row of `transcriptions.tsv` shows the lifecycle of a file:

| Status        | Meaning                                                           | Operator action                                                 |
| ------------- | ----------------------------------------------------------------- | --------------------------------------------------------------- |
| `in progress` | Whisper is currently transcribing.                                | Normally none. If stuck > expected time, see “Stuck job” below. |
| `complete`    | Successfully transcribed. Transcript path and exit code recorded. | None.                                                           |
| `error`       | Transcription failed (non-zero exit code or missing output).      | Investigate logs, correct issue, then reprocess if needed.      |

## 5. Common Tasks
### 5.1 Reprocess a failed file

1. Fix the underlying problem (e.g., corrupted media, missing codec).
2. Edit the state file and set the row’s status back to pending (or remove the line):
   ```
   nano /opt/transcriber/project/transcriptions.tsv
   ```
3. Force a run:
   ```
   systemctl start transcriber.service
   ```
   
### 5.2 Add or change allowed file types

1. Edit the EXTENSIONS array in `/opt/transcriber/scripts/transcriber.sh`
or update `/opt/transcriber/config/transcriber.env`.

2. Restart the timer to pick up the change:
   ```
   systemctl restart transcriber.timer
   ```
   
### 5.3 Change run frequency

If using systemd (recommended):
```
sudo nano /etc/systemd/system/transcriber.timer
# Adjust the OnCalendar line, e.g., OnCalendar=*:0/5 for every 5 minutes
sudo systemctl daemon-reload
sudo systemctl restart transcriber.timer
```

## 6. Troubleshooting

| Symptom                           | Likely cause                                           | Resolution                                                                                                                          |
| --------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| **No new transcripts appear**     | Whisper missing, bad permissions, or timer not running | Check `journalctl -u transcriber.service`, ensure Whisper is installed and executable.                                              |
| **Status stuck on `in progress`** | Whisper crashed or system shut down mid-process        | Inspect `transcriber.log` for errors. If safe, edit `transcriptions.tsv` and set status to `error` or remove the line, then re-run. |
| **Disk full**                     | Accumulated logs or transcripts                        | Check disk space with `df -h`, purge old transcripts or increase disk.                                                              |
| **Logs not rotating**             | logrotate misconfigured or disabled                    | Test with `sudo logrotate -f /etc/logrotate.conf` and check `/etc/logrotate.d/transcriber`.                                         |

## 7. Maintenance

### Log rotation

- Configured in `/etc/logrotate.d/transcriber`
- Keeps 7 compressed daily rotations of `transcriber.log` and `processed.log`.

Manual test:
`sudo logrotate -f /etc/logrotate.conf`

### Backups

- Regularly back up:
  - /opt/transcriber/project/transcriptions.tsv
  - /opt/transcriber/project/transcripts/
- These contain the permanent record of completed work and the transcript content.

### Upgrades

- Stop the timer:
  `sudo systemctl stop transcriber.timer`
- Replace `scripts/transcriber.sh` or configuration files.
- Reload and restart:
  ```
  sudo systemctl daemon-reload
  sudo systemctl start transcriber.timer
  ```

## 8. Escalation

If the above steps fail:

1. Capture the following files:

  - `/opt/transcriber/project/transcriber.log`
  - Output of journalctl -u transcriber.service
  - A sample problematic media file, if reproducible

2. Contact the maintainer with the above data.

## 9. References
  - OpenAI Whisper CLI
  - systemd.timer documentation
  - logrotate manual
  
| Date       | Version | Author      | Notes         |
| ---------- | ------- | ----------- | ------------- |
| 2025-09-15 | 0.1     | Mingtao Sun | Initial draft |

