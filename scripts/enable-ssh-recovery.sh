#!/usr/bin/env bash
# STEP 0 (do this FIRST, before touching any GPU/mux/firmware setting).
# Stand up SSH as a recovery net before we touch the GPU mux.
# Enables + starts sshd. Does NOT change sshd_config (uses distro defaults:
# password auth on, root login prohibited). You'll SSH in as your normal user.
set -euo pipefail

if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

echo "==> Enabling + starting sshd"
systemctl enable --now sshd

echo
echo "==> sshd status"
systemctl is-enabled sshd
systemctl is-active sshd
ss -tlnp 2>/dev/null | grep -E ':22\b' || echo "(port 22 not shown — check firewall)"

echo
echo "==> Firewall check (open :22 if a firewall is active)"
if systemctl is-active --quiet firewalld 2>/dev/null; then
  echo "firewalld active — opening ssh"; firewall-cmd --add-service=ssh --permanent; firewall-cmd --reload
elif command -v ufw >/dev/null && ufw status 2>/dev/null | grep -qi active; then
  echo "ufw active — allowing ssh"; ufw allow ssh
elif nft list ruleset 2>/dev/null | grep -q 'hook input'; then
  echo "NOTE: nftables rules present — verify :22 is allowed (see rules above)."
else
  echo "(no active host firewall detected — LAN SSH should reach it)"
fi

echo
echo "============================================================================"
echo "SSH RECOVERY READY."
echo "  From your other device, test NOW (while the screen works):"
echo "      ssh <user>@<your-machine-ip>"
echo "  (hostname also works if mDNS/avahi is up: ssh <user>@<hostname>.local )"
echo
echo "  Once logged in, confirm the recovery command exists and works:"
echo "      gpu-switch --help      # after we install it in a later step"
echo "============================================================================"
