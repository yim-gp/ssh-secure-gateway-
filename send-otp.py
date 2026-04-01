#!/usr/bin/env python3
import os
import smtplib
import sys
from pathlib import Path
from email.mime.text import MIMEText


ENV_FILE = Path("/usr/local/etc/gateway.env")


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")

    return values


def main() -> int:
    config = load_env_file(ENV_FILE)
    host = config.get("SMTP_HOST", "")
    port = int(config.get("SMTP_PORT", "587"))
    user = config.get("SMTP_USER", "")
    passwd = config.get("SMTP_PASS", "")
    to = config.get("OTP_TO", "")
    otp = os.environ.get("_OTP", "").strip()
    otp_ref = os.environ.get("_OTP_REF", "").strip()

    if not all([host, user, passwd, to, otp, otp_ref]):
        print("Mail error: missing OTP context or SMTP values in /usr/local/etc/gateway.env")
        return 1

    msg = MIMEText(
        f"Reference: {otp_ref}\n"
        f"OTP: {otp}\n\n"
        "Use this reference to match the latest OTP request.\n"
        "Valid for this session only."
    )
    msg["Subject"] = f"[Gateway] OTP Ref {otp_ref}"
    msg["From"] = user
    msg["To"] = to

    try:
        with smtplib.SMTP(host, port, timeout=20) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(user, passwd)
            smtp.sendmail(user, [to], msg.as_string())
    except Exception as exc:
        print(f"Mail error: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
