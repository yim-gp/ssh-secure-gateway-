#!/bin/bash

show_banner() {
  clear
  echo "╔══════════════════════════════════╗"
  echo "║        🔐 Secure Gateway         ║"
  echo "╚══════════════════════════════════╝"
  echo
}

show_menu() {
  echo "  [1] Open Shell"
  echo "  [2] System Info"
  echo "  [0] Exit"
  echo
}

# SSH forced command sessions may not inherit container env vars.
if [ -f /etc/gateway-otp.env ]; then
  # shellcheck source=/dev/null
  . /etc/gateway-otp.env
fi

AUDIT_LOG_FILE="${GATEWAY_AUDIT_LOG:-/var/log/gateway/open-shell-audit.jsonl}"
SESSION_ID="$(python3 -c "import secrets; print(secrets.token_hex(8))")"

get_remote_addr() {
  if [ -n "$SSH_CONNECTION" ]; then
    printf '%s' "${SSH_CONNECTION%% *}"
    return
  fi
  printf '%s' "unknown"
}

get_tty_name() {
  local tty_name

  if [ -n "$SSH_TTY" ]; then
    printf '%s' "$SSH_TTY"
    return
  fi

  tty_name=$(tty 2>/dev/null) || true
  if [ -n "$tty_name" ] && [ "$tty_name" != "not a tty" ]; then
    printf '%s' "$tty_name"
    return
  fi

  printf '%s' "unknown"
}

audit_log() {
  local event="$1"
  shift
  local log_dir timestamp remote_addr username tty_name

  log_dir=$(dirname "$AUDIT_LOG_FILE")
  mkdir -p "$log_dir" 2>/dev/null || true

  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  remote_addr=$(get_remote_addr)
  username=$(id -un 2>/dev/null || printf '%s' "unknown")
  tty_name=$(get_tty_name)

  TIMESTAMP="$timestamp" \
  EVENT_NAME="$event" \
  USERNAME="$username" \
  REMOTE_ADDR="$remote_addr" \
  SSH_TTY_VALUE="$tty_name" \
  SSH_CONNECTION_VALUE="${SSH_CONNECTION:-}" \
  SSH_CLIENT_VALUE="${SSH_CLIENT:-}" \
  SSH_ORIGINAL_COMMAND_VALUE="${SSH_ORIGINAL_COMMAND:-}" \
  SESSION_ID_VALUE="$SESSION_ID" \
  AUDIT_LOG_PATH="$AUDIT_LOG_FILE" \
  python3 - "$@" <<'PY' 2>/dev/null || true
import json
import os
import sys


def to_mapping(items: list[str]) -> dict[str, str]:
  mapping: dict[str, str] = {}
  for item in items:
    if "=" not in item:
      continue
    key, value = item.split("=", 1)
    mapping[key] = value
  return mapping


payload = {
  "timestamp": os.environ["TIMESTAMP"],
  "event": os.environ["EVENT_NAME"],
  "user": os.environ["USERNAME"],
  "remote_addr": os.environ["REMOTE_ADDR"],
  "pid": os.getppid(),
  "session_id": os.environ["SESSION_ID_VALUE"],
  "ssh_client": os.environ["SSH_CLIENT_VALUE"],
  "ssh_connection": os.environ["SSH_CONNECTION_VALUE"],
  "ssh_original_command": os.environ["SSH_ORIGINAL_COMMAND_VALUE"],
  "ssh_tty": os.environ["SSH_TTY_VALUE"],
}
payload.update(to_mapping(sys.argv[1:]))

with open(os.environ["AUDIT_LOG_PATH"], "a", encoding="utf-8") as handle:
  handle.write(json.dumps(payload, separators=(",", ":"), sort_keys=True))
  handle.write("\n")
PY
}

MAX_OTP_REQUESTS_PER_SESSION=5
OTP_REQUEST_COUNT=0

while true; do
  show_banner
  show_menu
  read -p "Select option: " choice

  case "$choice" in
    1)
      audit_log "open_shell_selected" "otp_requests_used=$OTP_REQUEST_COUNT"
      if [ "$OTP_REQUEST_COUNT" -ge "$MAX_OTP_REQUESTS_PER_SESSION" ]; then
        audit_log "open_shell_blocked" "reason=otp_request_limit_exceeded" "otp_requests_used=$OTP_REQUEST_COUNT"
        echo
        echo "❌ OTP request limit exceeded for this session. Disconnecting..."
        sleep 1
        exit 1
      fi
      OTP_REQUEST_COUNT=$((OTP_REQUEST_COUNT + 1))
      REMAINING_REQUESTS=$((MAX_OTP_REQUESTS_PER_SESSION - OTP_REQUEST_COUNT))
      echo
      echo "⏳ Sending OTP to your email..."
      OTP_TTL=120
      OTP_REF=$(python3 -c "import secrets, string; alphabet = string.ascii_uppercase + string.digits; print(''.join(secrets.choice(alphabet) for _ in range(6)))")
      OTP=$(python3 -c "import secrets; print(f'{secrets.randbelow(1_000_000):06d}')")
      OTP_ISSUED_AT=$(date +%s)
      _OTP_REF="$OTP_REF" _OTP="$OTP" _OTP_TTL="$OTP_TTL" python3 /usr/local/bin/send-otp.py
      SEND_STATUS=$?
      if [ $SEND_STATUS -ne 0 ]; then
        audit_log "otp_send_failed" "otp_ref=$OTP_REF" "send_status=$SEND_STATUS"
        echo "❌ Failed to send OTP. Contact admin."
        sleep 2
        continue
      fi
      audit_log "otp_sent" "otp_ref=$OTP_REF" "otp_ttl=$OTP_TTL" "remaining_requests=$REMAINING_REQUESTS"
      echo "✅ OTP sent. Check your email."
      echo "Reference: $OTP_REF"
      echo "OTP expires in 2 minutes."
      echo "OTP requests remaining this session: $REMAINING_REQUESTS"
      echo
      MAX_OTP_ATTEMPTS=3
      OTP_VALIDATED=0
      ATTEMPT=1
      while [ "$ATTEMPT" -le "$MAX_OTP_ATTEMPTS" ]; do
        read -s -p "Enter OTP (attempt $ATTEMPT/$MAX_OTP_ATTEMPTS): " input_otp
        echo
        OTP_NOW=$(date +%s)
        OTP_AGE=$((OTP_NOW - OTP_ISSUED_AT))
        if [ "$OTP_AGE" -gt "$OTP_TTL" ]; then
          audit_log "otp_expired" "otp_ref=$OTP_REF" "otp_age=$OTP_AGE" "attempt=$ATTEMPT"
          echo "⌛ OTP expired. Please request a new OTP."
          break
        fi
        if [ "$input_otp" = "$OTP" ]; then
          OTP_VALIDATED=1
          audit_log "otp_validated" "otp_ref=$OTP_REF" "attempt=$ATTEMPT"
          break
        fi
        REMAINING=$((MAX_OTP_ATTEMPTS - ATTEMPT))
        audit_log "otp_invalid" "otp_ref=$OTP_REF" "attempt=$ATTEMPT" "remaining_attempts=$REMAINING"
        if [ "$REMAINING" -gt 0 ]; then
          echo "❌ Invalid OTP ($REMAINING attempt(s) remaining)"
        else
          echo "❌ Invalid OTP. Maximum attempts reached."
        fi
        ATTEMPT=$((ATTEMPT + 1))
      done
      if [ "$OTP_VALIDATED" -ne 1 ]; then
        audit_log "open_shell_denied" "reason=otp_validation_failed" "otp_ref=$OTP_REF"
        OTP=""
        OTP_REF=""
        OTP_ISSUED_AT=0
        sleep 2
        continue
      fi
      SHELL_AUDIT_REF="$OTP_REF"
      OTP=""
      OTP_REF=""
      OTP_ISSUED_AT=0
      echo "✅ Access granted"
      sleep 1
      echo "Opening shell... (type 'exit' to return to menu)"
      audit_log "shell_opened" "otp_ref=$SHELL_AUDIT_REF"
      bash
      SHELL_STATUS=$?
      audit_log "shell_closed" "otp_ref=$SHELL_AUDIT_REF" "exit_status=$SHELL_STATUS"
      ;;
    2)
      show_banner
      echo "── System Info ──────────────────────"
      echo "Hostname : $(hostname)"
      echo "Date     : $(date)"
      echo "Uptime   : $(uptime -p 2>/dev/null || uptime)"
      echo "Kernel   : $(uname -r)"
      echo "Memory   : $(free -h 2>/dev/null | awk '/^Mem:/{print $3"/"$2}' || echo 'N/A')"
      echo "────────────────────────────────────"
      echo
      read -p "Press Enter to return to menu..." _
      ;;
    0)
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo "Invalid option."
      sleep 1
      ;;
  esac
done
