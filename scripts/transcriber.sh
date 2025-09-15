#!/usr/bin/env bash
set -euo pipefail

# ============ CONFIG ============
ENV_FILE="$(dirname "$0")/../config/transcriber.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# Copy-in progress detection
SIZE_CHECK_INTERVAL=2                       # seconds between size checks
SIZE_CHECK_RETRIES=2                        # how many times to see "stable" size

# ============ UTILS ============

timestamp() { date +"%Y-%m-%d %H:%M:%S%z"; }

log() {
  printf "[%s] %s\n" "$(timestamp)" "$*" | tee -a "$RUN_LOG" >/dev/null
}

ensure_files() {
  mkdir -p "$PROJECT_DIR" "$OUTPUT_DIR"
  touch "$STATE_FILE" "$RUN_LOG" "$PROCESSED_LOG"
}

# TSV-safe print (tab-separated, no newlines)
tsv_print() {
  # $1..$n fields
  local out=""
  for f in "$@"; do
    # replace newlines and tabs to keep TSV consistent
    f=${f//$'\n'/'⏎'}
    f=${f//$'\t'/'␉'}
    out+="$f"$'\t'
  done
  # trim trailing tab and print
  printf "%s\n" "${out%$'\t'}"
}

# Lookup status by exact filepath
get_status() {
  local f="$1"
  awk -v path="$f" -F'\t' '$2==path{print $3; exit}' "$STATE_FILE"
}

# Upsert a row for filepath with new status and optional transcript/exit
# This rewrites the file atomically to avoid corruption.
set_status() {
  local f="$1" new_status="$2" transcript="${3:-}" exit_code="${4:-}"
  local tmp="${STATE_FILE}.tmp.$$"
  awk -v now="$(timestamp)" -v path="$f" -v status="$new_status" -v tpath="$transcript" -v code="$exit_code" -F'\t' 'BEGIN{updated=0}
    $2==path {
      $1=now; $3=status;
      if (tpath!="") $4=tpath;
      if (code!="") $5=code;
      print $0; updated=1; next
    }
    {print $0}
    END{
      if(!updated){
        # new row: ts, filepath, status, transcript_path, exit_code
        printf "%s\t%s\t%s\t%s\t%s\n", now, path, status, tpath, code
      }
    }' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# Check if file size is stable to avoid half-copied files
is_stable() {
  local f="$1"
  local last_size=-1 same_count=0
  for _ in $(seq 0 "$SIZE_CHECK_RETRIES"); do
    local sz
    sz=$(stat -c%s -- "$f" 2>/dev/null || echo -1)
    [[ "$sz" -ge 0 ]] || return 1
    if [[ "$sz" -eq "$last_size" ]]; then
      same_count=$((same_count+1))
      if [[ "$same_count" -ge 1 ]]; then
        return 0
      fi
    else
      same_count=0
      last_size="$sz"
      sleep "$SIZE_CHECK_INTERVAL"
    fi
  done
  return 1
}

# Discover candidate files
discover_files() {
  local -a find_args=( -maxdepth "$SCAN_DEPTH" -type f )
  # Build extension OR-list
  local first=1
  for ext in "${EXTENSIONS[@]}"; do
    if [[ $first -eq 1 ]]; then
      find_args+=( \( -iname "*.${ext}" )
      first=0
    else
      find_args+=( -o -iname "*.${ext}" )
    fi
  done
  if [[ $first -eq 0 ]]; then
    find_args+=( \) )
  fi
  find "$PROJECT_DIR" "${find_args[@]}"
}

# ============ MAIN ============

main() {
  ensure_files

  # Global lock to prevent overlap
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    log "Another run is in progress; exiting."
    exit 0
  fi

  log "Scan start."

  local any=0
  while IFS= read -r file; do
    # Skip files in transcripts/output dirs
    [[ "$file" == "$OUTPUT_DIR"* ]] && continue
    # Normalize to absolute path
    file="$(readlink -f -- "$file")"

    # Check state
    status="$(get_status "$file" || true)"
    if [[ "$status" == "in progress" || "$status" == "complete" ]]; then
      # already handled
      continue
    fi

    # Avoid half-copied files
    if ! is_stable "$file"; then
      log "Skipping (not stable yet): $file"
      continue
    fi

    any=1
    set_status "$file" "in progress"
    log "Transcribing: $file"

    # Run Whisper
    set +e
    "$WHISPER_BIN" "$file" --model "$WHISPER_MODEL" --output_dir "$OUTPUT_DIR" --output_format "$OUTPUT_FORMAT"
    rc=$?
    set -e

    # Whisper writes $OUTPUT_DIR/<basename>.<lang>.txt (varies by build).
    # We’ll record the most recent .txt matching the basename.
    base="$(basename -- "$file")"
    stem="${base%.*}"
    transcript_path="$(ls -t "$OUTPUT_DIR"/"$stem"*".txt" 2>/dev/null | head -n1 || true)"

    if [[ $rc -eq 0 && -n "$transcript_path" && -s "$transcript_path" ]]; then
      set_status "$file" "complete" "$transcript_path" "0"
      log "✅ Complete: $file -> $transcript_path"
      tsv_print "$(timestamp)" "$file" "complete" "$transcript_path" "0" >> "$PROCESSED_LOG"
    else
      set_status "$file" "error" "$transcript_path" "$rc"
      log "❌ Error ($rc): $file (transcript: ${transcript_path:-none})"
      tsv_print "$(timestamp)" "$file" "error" "${transcript_path:-}" "$rc" >> "$PROCESSED_LOG"
    fi

  done < <(discover_files)

  if [[ $any -eq 0 ]]; then
    log "No new files."
  fi

  log "Scan end."
}

main "$@"

