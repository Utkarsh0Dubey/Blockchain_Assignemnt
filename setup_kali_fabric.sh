#!/usr/bin/env bash
set -euo pipefail

echo "== Update system =="
sudo apt update -y
sudo apt upgrade -y

echo "== Install Docker & docker-compose =="
sudo apt install -y docker.io docker-compose git curl jq
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER || true

echo "== Install Node.js LTS =="
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

echo "== Bootstrap Hyperledger Fabric samples & binaries (2.5.0) =="
cd ~
curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.0
echo 'export PATH=$PATH:$HOME/fabric-samples/bin' >> ~/.bashrc

echo "== Versions =="
docker --version || true
node -v || true
npm -v || true
peer version || true || echo "(peer will be in PATH after relogin/sourcing .bashrc)"

echo
echo "✅ Setup complete. IMPORTANT:"
echo "  • Open a NEW terminal or: source ~/.bashrc"
echo "  • If docker perms fail: newgrp docker"
