# Gateway V2

Gateway V2 is an SSH gateway that forces users through a menu-driven shell and sends a one-time password (OTP) by email before opening an interactive shell.

## What This Repository Contains

- `docker-compose.yml`: Docker deployment entrypoint.
- `Dockerfile`: Ubuntu-based image with OpenSSH and Python.
- `docker-entrypoint.sh`: Container bootstrap for SSH and forced command setup.
- `gateway-shell.sh`: Interactive gateway menu and OTP validation flow.
- `send-otp.py`: SMTP mail sender for OTP delivery.
- `.env.example`: Template for required mail configuration.
- `docs/runbook-recovery.md`: Recovery and rollback steps.
- `docs/troubleshooting.md`: Debugging flow for common failures.

## How The Flow Works

1. User connects through SSH.
2. SSH forces `gateway-shell.sh` instead of a normal login shell.
3. The menu triggers OTP generation.
4. `send-otp.py` sends the OTP to the configured email recipients.
5. If the OTP is correct and not expired, the user gets a shell.
6. Each `Open Shell` attempt is appended as JSONL to `/var/log/gateway/open-shell-audit.jsonl` unless `GATEWAY_AUDIT_LOG` overrides the path.

## Prerequisites

### Docker deployment

- Docker Engine 24+ or Docker Desktop with Compose support.
- Port `2222` open on the host.
- A working SMTP account that allows SMTP login.

### Native Linux deployment

- Ubuntu 22.04 or another modern Debian-based Linux host.
- `openssh-server`, `python3`, and `sudo` installed.
- Root or sudo privileges for setup.
- A working SMTP account that allows SMTP login.

## Quick Start With Docker

1. Create the environment file from the template.

```bash
cp .env.example .env
```

2. Edit `.env` and fill in real SMTP values.

3. Build and start the gateway.

```bash
docker compose up --build -d
```

4. Check logs.

```bash
docker compose logs -f gateway
```

5. Connect to the gateway.

```bash
ssh limited@127.0.0.1 -p 2222
```

Default image behavior currently creates the `limited` user with password `limited123`. Treat this as a bootstrap-only setup and rotate it before any real use.

## Docker Operations

### Rebuild after script changes

```bash
docker compose down
docker compose up --build -d
```

### Inspect container state

```bash
docker compose ps
docker compose logs --tail=100 gateway
docker exec -it gateway-v2 /bin/bash
ls -l ./logs/gateway
```

### Validate mounted files inside the container

```bash
docker exec gateway-v2 ls -l /usr/local/bin/gateway-shell.sh /usr/local/bin/send-otp.py /usr/local/etc/gateway.env
```

## Native Linux Installation

The native setup mirrors the container paths so that the scripts behave the same way.

1. Install packages.

```bash
sudo apt update
sudo apt install -y openssh-server sudo python3 python3-pip
```

2. Create required directories.

```bash
sudo mkdir -p /usr/local/bin /usr/local/etc /var/log/gateway
```

3. Copy project files into system paths.

```bash
sudo cp gateway-shell.sh /usr/local/bin/gateway-shell.sh
sudo cp send-otp.py /usr/local/bin/send-otp.py
sudo cp .env.example /usr/local/etc/gateway.env
sudo chmod 755 /usr/local/bin/gateway-shell.sh
sudo chmod 644 /usr/local/bin/send-otp.py
sudo chmod 600 /usr/local/etc/gateway.env
```

4. Edit `/usr/local/etc/gateway.env` with real SMTP values.

5. Create the SSH user.

```bash
sudo useradd -m limited
sudo passwd limited
sudo chown limited:limited /var/log/gateway
sudo chmod 750 /var/log/gateway
sudo touch /var/log/gateway/open-shell-audit.jsonl
sudo chown limited:limited /var/log/gateway/open-shell-audit.jsonl
sudo chmod 640 /var/log/gateway/open-shell-audit.jsonl
```

6. Register the forced shell.

```bash
grep -qxF /usr/local/bin/gateway-shell.sh /etc/shells || echo /usr/local/bin/gateway-shell.sh | sudo tee -a /etc/shells
sudo chsh -s /usr/local/bin/gateway-shell.sh limited
```

7. Update `sshd_config`.

Add this block if it does not already exist:

```text
Match User limited
  ForceCommand /usr/local/bin/gateway-shell.sh
  AllowTcpForwarding no
  X11Forwarding no
```

8. Restart SSH.

```bash
sudo systemctl restart ssh
sudo systemctl status ssh --no-pager
```

9. Test the login flow.

```bash
ssh limited@YOUR_SERVER_IP
```

## Verification Checklist

- `sshd` is running.
- `gateway-shell.sh` is executable.
- `send-otp.py` exists at `/usr/local/bin/send-otp.py`.
- SMTP variables are present in `/usr/local/etc/gateway.env`.
- You receive an OTP email after selecting `Open Shell`.
- Entering the OTP opens a shell and `exit` returns to the gateway menu.
- Open shell audit entries are written to `/var/log/gateway/open-shell-audit.jsonl`.

## Audit Log

The gateway keeps a best-effort history of `Open Shell` usage in:

```bash
/var/log/gateway/open-shell-audit.jsonl
```

In Docker deployments, that path is bind-mounted to the host at:

```bash
./logs/gateway/open-shell-audit.jsonl
```

Each line is a standalone JSON object with fields such as `timestamp`, `event`, `user`, `remote_addr`, `pid`, `session_id`, `ssh_client`, `ssh_connection`, `ssh_original_command`, `ssh_tty`, `otp_ref`, and `exit_status`.

For a normal interactive SSH login, `ssh_original_command` is expected to be empty. It is populated only when the client connects with a remote command.

Example:

```json
{"event":"shell_opened","otp_ref":"AB12CD","pid":1234,"remote_addr":"127.0.0.1","session_id":"d4c0e9d2f7f74d9b","ssh_client":"127.0.0.1 57772 2222","ssh_connection":"127.0.0.1 57772 172.18.0.2 22","ssh_original_command":"","ssh_tty":"/dev/pts/0","timestamp":"2026-04-02T12:34:56Z","user":"limited"}
```

You can override the destination path by setting `GATEWAY_AUDIT_LOG` before launching the shell script.

## Onboarding For New Team Members

1. Read this file once from top to bottom.
2. Copy `.env.example` to `.env` for Docker or to `/usr/local/etc/gateway.env` for native Linux.
3. Start with Docker first, because it is easier to reset.
4. Use the troubleshooting flow in `docs/troubleshooting.md` if OTP delivery or SSH access fails.
5. Use the recovery runbook in `docs/runbook-recovery.md` before changing SSH configuration on a real host.

## Security Notes

- Do not commit `.env`.
- Rotate SMTP credentials if they were ever stored in plaintext outside a secret manager.
- Remove the bootstrap password and `NOPASSWD` sudo before production use.
- Consider SSH key authentication and central logging before exposing this gateway publicly.

## Related Docs

- [Recovery runbook](docs/runbook-recovery.md)
- [Troubleshooting flow](docs/troubleshooting.md)