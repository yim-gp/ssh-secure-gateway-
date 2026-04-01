#!/usr/bin/env python3
import os
import smtplib
import sys
from html import escape
from pathlib import Path
from email.mime.multipart import MIMEMultipart
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
    to_raw = config.get("OTP_TO", "")
    recipients = [
        addr.strip()
        for addr in to_raw.replace(";", ",").split(",")
        if addr.strip()
    ]
    otp = os.environ.get("_OTP", "").strip()
    otp_ref = os.environ.get("_OTP_REF", "").strip()

    if not all([host, user, passwd, recipients, otp, otp_ref]):
        print("Mail error: missing OTP context or SMTP values in /usr/local/etc/gateway.env")
        return 1

    safe_otp = escape(otp)
    safe_otp_ref = escape(otp_ref)

    text_body = (
        "Gateway OTP Verification\n\n"
        f"Reference: {otp_ref}\n"
        f"OTP: {otp}\n\n"
        "Use this reference to match the latest OTP request.\n"
        "This OTP is valid for this session only."
    )

    html_body = f"""\
<html>
    <body style=\"margin:0;padding:0;background:#f4f6fb;font-family:Arial,Helvetica,sans-serif;color:#1d2939;\">
        <table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"background:#f4f6fb;padding:24px 12px;\">
            <tr>
                <td align=\"center\">
                    <table role=\"presentation\" width=\"560\" cellspacing=\"0\" cellpadding=\"0\" style=\"max-width:560px;background:#ffffff;border:1px solid #e4e7ec;border-radius:14px;overflow:hidden;\">
                        <tr>
                            <td style=\"background:linear-gradient(135deg,#155eef,#004eeb);padding:20px 24px;color:#ffffff;font-size:18px;font-weight:700;\">
                                Gateway OTP Verification
                            </td>
                        </tr>
                        <tr>
                            <td style=\"padding:24px;\">
                                <p style=\"margin:0 0 14px 0;font-size:14px;line-height:1.6;\">Your one-time password request is ready.</p>
                                <table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"margin:0 0 16px 0;background:#f8f9fc;border:1px solid #eaecf0;border-radius:10px;\">
                                    <tr>
                                        <td style=\"padding:16px 18px;\">
                                            <p style=\"margin:0 0 8px 0;font-size:12px;color:#475467;letter-spacing:0.02em;\">Reference</p>
                                            <p style=\"margin:0;font-size:16px;font-weight:700;color:#101828;\">{safe_otp_ref}</p>
                                        </td>
                                    </tr>
                                </table>
                                <p style=\"margin:0 0 10px 0;font-size:12px;color:#475467;letter-spacing:0.02em;\">OTP Code</p>
                                <p style=\"margin:0 0 16px 0;font-size:32px;line-height:1.1;font-weight:800;letter-spacing:8px;color:#155eef;\">{safe_otp}</p>
                                <p style=\"margin:0;font-size:13px;line-height:1.6;color:#475467;\">
                                    Use this reference to match the latest OTP request.<br>
                                    This OTP is valid for this session only.
                                </p>
                            </td>
                        </tr>
                        <tr>
                            <td style=\"padding:14px 24px;background:#f9fafb;border-top:1px solid #eaecf0;font-size:12px;line-height:1.6;color:#667085;\">
                                This is an automated message from Gateway. Please do not reply.
                            </td>
                        </tr>
                    </table>
                </td>
            </tr>
        </table>
    </body>
</html>
"""

    msg = MIMEMultipart("alternative")
    msg["Subject"] = f"[Gateway] OTP Ref {otp_ref}"
    msg["From"] = user
    msg["To"] = ", ".join(recipients)
    msg.attach(MIMEText(text_body, "plain", "utf-8"))
    msg.attach(MIMEText(html_body, "html", "utf-8"))

    try:
        with smtplib.SMTP(host, port, timeout=20) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(user, passwd)
            smtp.sendmail(user, recipients, msg.as_string())
    except Exception as exc:
        print(f"Mail error: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
