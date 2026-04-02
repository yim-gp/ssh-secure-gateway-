# Recovery Runbook

Use this runbook when a deployment breaks SSH login, OTP delivery, or the forced command flow.

## Recovery Goals

- Restore administrator access.
- Restore mail delivery for OTP.
- Restore the forced command shell for the `limited` user.
- Roll back quickly without editing too many moving parts at once.

## Safe Recovery Order

1. Confirm you still have root, console, or out-of-band access.
2. Restore plain SSH access for an admin account before touching the gateway account.
3. Fix mail configuration.
4. Re-enable the forced command flow.
5. Test with a fresh SSH session.

## Docker Recovery

### Stop the broken container

```bash
docker compose down
```

### Inspect the current project state

```bash
docker compose config
docker compose logs gateway
```

### Verify local files before restart

```bash
ls -l gateway-shell.sh send-otp.py send-otp-helper.sh .env
bash -n gateway-shell.sh
bash -n send-otp-helper.sh
python3 -m py_compile send-otp.py
```

### Restart cleanly

```bash
docker compose up --build -d
docker compose logs -f gateway
```

### Emergency rollback option

If a recent local edit broke the gateway flow, restore the known-good version from git and rebuild.

```bash
git diff
git log --oneline -n 5
```

Apply the rollback only after reviewing the diff carefully.

## Native Linux Recovery

### Recover SSH access first

If the forced command blocks all access for `limited`, switch the shell temporarily to `/bin/bash`.

```bash
sudo chsh -s /bin/bash limited
```

If `sshd_config` was changed incorrectly, comment out the `Match User limited` block temporarily and restart SSH.

```bash
sudoedit /etc/ssh/sshd_config
sudo sshd -t
sudo systemctl restart ssh
```

### Restore gateway files

```bash
sudo cp gateway-shell.sh /usr/local/bin/gateway-shell.sh
sudo cp send-otp.py /usr/local/bin/send-otp.py
sudo cp send-otp-helper.sh /usr/local/bin/send-otp-helper.sh
sudo chmod 755 /usr/local/bin/gateway-shell.sh
sudo chmod 750 /usr/local/bin/send-otp-helper.sh
sudo chmod 644 /usr/local/bin/send-otp.py
```

### Restore mail config

```bash
sudoedit /usr/local/etc/gateway.env
sudo chmod 600 /usr/local/etc/gateway.env
echo 'limited ALL=(root) NOPASSWD: /usr/local/bin/send-otp-helper.sh' | sudo tee /etc/sudoers.d/limited-send-otp >/dev/null
sudo chmod 440 /etc/sudoers.d/limited-send-otp
```

### Re-enable the forced shell

```bash
grep -qxF /usr/local/bin/gateway-shell.sh /etc/shells || echo /usr/local/bin/gateway-shell.sh | sudo tee -a /etc/shells
sudo chsh -s /usr/local/bin/gateway-shell.sh limited
sudo sshd -t
sudo systemctl restart ssh
```

## Mail Recovery Checks

1. Verify `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, and `OTP_TO` are set.
2. Confirm the SMTP provider allows the login method being used.
3. Check whether the provider requires an app password instead of the main account password.
4. Review stderr output from `send-otp.py` or `/usr/local/bin/send-otp-helper.sh` for authentication or TLS errors.

## Exit Criteria

Recovery is complete only when:

- SSH login reaches the menu.
- OTP mail is delivered.
- A valid OTP opens a shell.
- `exit` returns to the gateway menu.