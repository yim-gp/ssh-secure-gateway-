FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    openssh-server sudo passwd python3 python3-pip && \
    mkdir -p /var/run/sshd && \
    rm -rf /var/lib/apt/lists/*

# สร้าง user
RUN useradd -m limited && echo "limited:limited123" | chpasswd

# Allow only the OTP helper to run with sudo.
RUN printf 'limited ALL=(root) NOPASSWD: /usr/local/bin/send-otp-helper.sh\n' > /etc/sudoers.d/limited-send-otp && \
    chmod 440 /etc/sudoers.d/limited-send-otp

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY send-otp-helper.sh /usr/local/bin/send-otp-helper.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/send-otp-helper.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
