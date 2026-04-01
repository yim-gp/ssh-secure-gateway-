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

while true; do
  show_banner
  show_menu
  read -p "Select option: " choice

  case "$choice" in
    1)
      echo
      echo "⏳ Sending OTP to your email..."
      OTP_REF=$(python3 -c "import random, string; print(''.join(random.choices(string.ascii_uppercase + string.digits, k=6)))")
      OTP=$(python3 -c "import random; print(f'{random.randint(0,999999):06d}')")
      _OTP_REF="$OTP_REF" _OTP="$OTP" python3 /usr/local/bin/send-otp.py
      SEND_STATUS=$?
      if [ $SEND_STATUS -ne 0 ]; then
        echo "❌ Failed to send OTP. Contact admin."
        sleep 2
        continue
      fi
      echo "✅ OTP sent. Check your email."
      echo "Reference: $OTP_REF"
      echo
      read -s -p "Enter OTP: " input_otp
      echo
      if [ "$input_otp" != "$OTP" ]; then
        echo "❌ Invalid OTP"
        sleep 2
        continue
      fi
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
