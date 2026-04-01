#!/usr/bin/env python3
import os
import smtplib
import sys
from email.mime.text import MIMEText


def main() -> int:
    host = 'smtp.gmail.com'
    # host = os.environ.get("SMTP_HOST", "").strip()
    port = 587
    # port = int(os.environ.get("SMTP_PORT", "587"))
    user = "***REMOVED***"
    # user = os.environ.get("SMTP_USER", "").strip()
    passwd = "***REMOVED***"
    # passwd = os.environ.get("SMTP_PASS", "").strip()
    to = 'pongsapuk@growpro.co.th'
    # to = os.environ.get("OTP_TO", "").strip()
    otp = os.environ.get("_OTP", "").strip()
    otp_ref = os.environ.get("_OTP_REF", "").strip()

    if not all([host, user, passwd, to, otp, otp_ref]):
        print("Mail error: missing SMTP env values (SMTP_HOST/SMTP_USER/SMTP_PASS/OTP_TO)")
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
