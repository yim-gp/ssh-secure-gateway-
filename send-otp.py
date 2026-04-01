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
    otp_ttl_seconds = int(os.environ.get("_OTP_TTL", "120") or "120")
    otp_ttl_minutes = max(1, otp_ttl_seconds // 60)

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
        f"This OTP expires in {otp_ttl_minutes} minute(s)."
    )

    html_body = f"""\
<html>
    <head>
        <meta name=\"color-scheme\" content=\"light dark\">
        <meta name=\"supported-color-schemes\" content=\"light dark\">
        <style>
            @media (prefers-color-scheme: dark) {{
                body, .page {{ background:#111417 !important; color:#e5e7eb !important; }}
                .card {{ background:#1a1f24 !important; border-color:#2a3138 !important; }}
                .header {{ background:#2b3440 !important; color:#f3f4f6 !important; }}
                .subtle-box {{ background:#20262d !important; border-color:#323a43 !important; }}
                .label {{ color:#9ca3af !important; }}
                .value {{ color:#f3f4f6 !important; }}
                .otp {{ color:#93c5fd !important; }}
                .note {{ color:#cbd5e1 !important; }}
                .footer {{ background:#151a1f !important; border-color:#2a3138 !important; color:#9ca3af !important; }}
            }}
        </style>
    </head>
    <body class=\"page\" style=\"margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;color:#1f2937;\">
        <table role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"background:#f3f4f6;padding:24px 12px;\">
            <tr>
                <td align=\"center\">
                    <table class=\"card\" role=\"presentation\" width=\"560\" cellspacing=\"0\" cellpadding=\"0\" style=\"max-width:560px;background:#ffffff;border:1px solid #d1d5db;border-radius:14px;overflow:hidden;\">
                        <tr>
                            <td class=\"header\" style=\"background:#374151;padding:20px 24px;color:#f9fafb;font-size:18px;font-weight:700;\">
                                Gateway OTP Verification
                            </td>
                        </tr>
                        <tr>
                            <td style=\"padding:24px;\">
                                <p class=\"note\" style=\"margin:0 0 14px 0;font-size:14px;line-height:1.6;color:#374151;\">Your one-time password request is ready.</p>
                                <table class=\"subtle-box\" role=\"presentation\" width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"margin:0 0 16px 0;background:#f9fafb;border:1px solid #e5e7eb;border-radius:10px;\">
                                    <tr>
                                        <td style=\"padding:16px 18px;\">
                                            <p class=\"label\" style=\"margin:0 0 8px 0;font-size:12px;color:#6b7280;letter-spacing:0.02em;\">Reference</p>
                                            <p class=\"value\" style=\"margin:0;font-size:16px;font-weight:700;color:#111827;\">{safe_otp_ref}</p>
                                        </td>
                                    </tr>
                                </table>
                                <p class=\"label\" style=\"margin:0 0 10px 0;font-size:12px;color:#6b7280;letter-spacing:0.02em;\">OTP Code</p>
                                <p class=\"otp\" style=\"margin:0 0 16px 0;font-size:32px;line-height:1.1;font-weight:800;letter-spacing:8px;color:#1d4ed8;\">{safe_otp}</p>
                                <p class=\"note\" style=\"margin:0;font-size:13px;line-height:1.6;color:#4b5563;\">
                                    Use this reference to match the latest OTP request.<br>
                                    This OTP expires in {otp_ttl_minutes} minute(s).
                                </p>
                            </td>
                        </tr>
                        <tr>
                            <td class=\"footer\" style=\"padding:14px 24px;background:#f9fafb;border-top:1px solid #e5e7eb;font-size:12px;line-height:1.6;color:#6b7280;\">
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
