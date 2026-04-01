FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    openssh-server sudo passwd python3 python3-pip && \
    mkdir -p /var/run/sshd && \
    rm -rf /var/lib/apt/lists/*

# สร้าง user
RUN useradd -m limited && echo "limited:limited123" | chpasswd

# อนุญาต sudo (optional)
RUN echo "limited ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]
