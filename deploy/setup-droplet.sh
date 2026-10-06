#!/bin/sh
# One-time setup for a fresh Ubuntu droplet. Run as root:  sh setup-droplet.sh
set -eu

# Docker
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

# 2 GB swap so a 1 GB droplet survives memory spikes
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swap.conf
  sysctl -p /etc/sysctl.d/99-swap.conf
fi

# Firewall: SSH + web only
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

mkdir -p /opt/sketchy
echo "Done. Copy deploy/docker-compose.yml, deploy/Caddyfile and your .env into /opt/sketchy."
