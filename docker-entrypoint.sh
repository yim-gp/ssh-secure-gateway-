#!/bin/bash
set -e

SCRIPT_PATH="/usr/local/bin/gateway-shell.sh"
HELPER_PATH="/usr/local/bin/send-otp-helper.sh"
SSHD_CONFIG="/etc/ssh/sshd_config"
OTP_ENV_FILE="/etc/gateway-otp.env"
SHELL_ENV_FILE="/etc/gateway-shell.env"
AUDIT_LOG_FILE="${GATEWAY_AUDIT_LOG:-/var/log/gateway/open-shell-audit.json}"
AUDIT_LOG_DIR="$(dirname "$AUDIT_LOG_FILE")"

# If no mounted script exists, create a safe default fallback.
if [ ! -f "$SCRIPT_PATH" ]; then
  cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
clear
echo "=== Secure Gateway ==="
read -s -p "Enter access code: " code
echo
if [ "$code" != "4321" ]; then
  echo "Access denied"
  sleep 2
  exit 1
fi
echo "Access granted"
sleep 1
exec /bin/bash
EOF
fi

if [ ! -x "$SCRIPT_PATH" ]; then
  chmod +x "$SCRIPT_PATH" 2>/dev/null || true
fi

if [ ! -x "$SCRIPT_PATH" ]; then
  echo "gateway shell is not executable: $SCRIPT_PATH"
  exit 1
fi

if [ ! -x "$HELPER_PATH" ]; then
  chmod 750 "$HELPER_PATH" 2>/dev/null || true
fi

if [ ! -x "$HELPER_PATH" ]; then
  echo "OTP helper is not executable: $HELPER_PATH"
  exit 1
fi

grep -qxF "$SCRIPT_PATH" /etc/shells || echo "$SCRIPT_PATH" >> /etc/shells
chsh -s "$SCRIPT_PATH" limited || true

if ! grep -q "^Match User limited$" "$SSHD_CONFIG"; then
  cat >> "$SSHD_CONFIG" << 'EOF'

Match User limited
  ForceCommand /usr/local/bin/gateway-shell.sh
  AllowTcpForwarding no
  X11Forwarding no
EOF
fi

# Persist OTP mail config for SSH sessions where daemon env is not exposed.
{
  printf "export SMTP_HOST=%q\n" "${SMTP_HOST:-}"
  printf "export SMTP_PORT=%q\n" "${SMTP_PORT:-587}"
  printf "export SMTP_USER=%q\n" "${SMTP_USER:-}"
  printf "export SMTP_PASS=%q\n" "${SMTP_PASS:-}"
  printf "export OTP_TO=%q\n" "${OTP_TO:-}"
  printf "export GATEWAY_AUDIT_LOG=%q\n" "$AUDIT_LOG_FILE"
} > "$OTP_ENV_FILE"
chown root:root "$OTP_ENV_FILE"
chmod 600 "$OTP_ENV_FILE"

printf "export GATEWAY_AUDIT_LOG=%q\n" "$AUDIT_LOG_FILE" > "$SHELL_ENV_FILE"
chown root:limited "$SHELL_ENV_FILE"
chmod 640 "$SHELL_ENV_FILE"

mkdir -p "$AUDIT_LOG_DIR"
touch "$AUDIT_LOG_FILE"
chown -R limited:limited "$AUDIT_LOG_DIR"
chmod 750 "$AUDIT_LOG_DIR"
chmod 640 "$AUDIT_LOG_FILE"

exec "$@"
