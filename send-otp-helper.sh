#!/bin/bash
set -eu

OTP_ENV_FILE="/etc/gateway-otp.env"

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <otp_ref> <otp> <otp_ttl_seconds>" >&2
  exit 2
fi

if [ -f "$OTP_ENV_FILE" ]; then
  # shellcheck source=/dev/null
  . "$OTP_ENV_FILE"
fi

exec env \
  _OTP_REF="$1" \
  _OTP="$2" \
  _OTP_TTL="$3" \
  python3 /usr/local/bin/send-otp.py