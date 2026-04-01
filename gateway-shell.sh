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

MAX_OTP_REQUESTS_PER_SESSION=5
OTP_REQUEST_COUNT=0

while true; do
  show_banner
  show_menu
  read -p "Select option: " choice

  case "$choice" in
    1)
      if [ "$OTP_REQUEST_COUNT" -ge "$MAX_OTP_REQUESTS_PER_SESSION" ]; then
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
        echo "❌ Failed to send OTP. Contact admin."
        sleep 2
        continue
      fi
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
          echo "⌛ OTP expired. Please request a new OTP."
          break
        fi
        if [ "$input_otp" = "$OTP" ]; then
          OTP_VALIDATED=1
          break
        fi
        REMAINING=$((MAX_OTP_ATTEMPTS - ATTEMPT))
        if [ "$REMAINING" -gt 0 ]; then
          echo "❌ Invalid OTP ($REMAINING attempt(s) remaining)"
        else
          echo "❌ Invalid OTP. Maximum attempts reached."
        fi
        ATTEMPT=$((ATTEMPT + 1))
      done
      if [ "$OTP_VALIDATED" -ne 1 ]; then
        OTP=""
        OTP_REF=""
        OTP_ISSUED_AT=0
        sleep 2
        continue
      fi
      OTP=""
      OTP_REF=""
      OTP_ISSUED_AT=0
      echo "✅ Access granted"
      sleep 1
      echo "Opening shell... (type 'exit' to return to menu)"
      bash
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
