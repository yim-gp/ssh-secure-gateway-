# Troubleshooting Flow

Use this flow from top to bottom. Do not debug mail first if SSH itself is not working.

## 1. SSH Connection Fails Immediately

### Symptoms

- `Connection refused`
- `Connection reset`
- SSH client times out

### Checks

#### Docker

```bash
docker compose ps
docker compose logs --tail=100 gateway
docker port gateway-v2
```

#### Native Linux

```bash
sudo systemctl status ssh --no-pager
sudo ss -ltnp | grep ':22 '
sudo sshd -t
```

### Likely causes

- Container is not running.
- Port `2222` is not mapped or blocked.
- `sshd_config` is invalid.

## 2. SSH Login Works But Menu Does Not Appear

### Checks

```bash
ls -l /usr/local/bin/gateway-shell.sh
grep -n 'Match User limited' /etc/ssh/sshd_config
grep -n '/usr/local/bin/gateway-shell.sh' /etc/shells
```

### Likely causes

- Forced command block is missing.
- `gateway-shell.sh` is not executable.
- User shell is not set correctly.

## 3. Menu Appears But OTP Email Is Not Sent

### Checks

```bash
cat /usr/local/etc/gateway.env
python3 -m py_compile /usr/local/bin/send-otp.py
_OTP_REF=TEST01 _OTP=123456 _OTP_TTL=120 python3 /usr/local/bin/send-otp.py
```

### Likely causes

- SMTP credentials are wrong.
- SMTP provider blocks password login.
- Network egress to the SMTP server is blocked.
- `OTP_TO` is empty or malformed.

## 4. OTP Email Arrives But Login Still Fails

### Checks

1. Make sure you are entering the latest OTP for the displayed reference.
2. Confirm the OTP is entered before the 2-minute expiry.
3. Retry with a new OTP request.

### Likely causes

- OTP expired.
- A previous email was used instead of the latest one.
- Too many failed attempts were entered.

## 5. User Enters The Shell But Session Behavior Is Wrong

### Checks

```bash
whoami
pwd
env | grep -E 'SMTP|OTP'
```

### Likely causes

- Wrong user shell.
- Environment file was not loaded.
- User permissions or home directory are broken.

## 6. One-Command Sanity Checks

### Docker

```bash
docker exec gateway-v2 bash -lc 'pgrep -x sshd && [ -x /usr/local/bin/gateway-shell.sh ] && [ -f /usr/local/bin/send-otp.py ] && [ -r /usr/local/etc/gateway.env ] && echo ok'
```

### Native Linux

```bash
pgrep -x sshd && [ -x /usr/local/bin/gateway-shell.sh ] && [ -f /usr/local/bin/send-otp.py ] && [ -r /usr/local/etc/gateway.env ] && echo ok
```

## Escalation Path

1. Fix SSH daemon problems first.
2. Fix forced shell and file permissions second.
3. Fix SMTP and OTP delivery third.
4. Only after those pass, investigate OTP validation logic.