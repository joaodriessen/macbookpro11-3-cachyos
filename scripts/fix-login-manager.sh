#!/usr/bin/env bash
# Fix: plasmalogin's greeter always renders via kwin_wayland, which requires GBM.
# nvidia-470xx (the only driver that supports this Mac's GK107M/GT750M Kepler chip)
# has no GBM support, so the greeter SIGSEGVs before a login screen ever appears —
# this happens regardless of which session you intend to log into, since it's the
# greeter itself that crashes, before you ever reach a session picker.
# Fix: switch to SDDM with its greeter forced to X11, bypassing kwin_wayland/GBM
# entirely. The "Plasma (X11)" session (plasmax11.desktop) already exists and works.
#
# NOTE: this script predates the full Intel-only migration — it was the fix while
# still running nvidia-470xx. Once nvidia is fully blacklisted (see nvidia-off.sh)
# and Intel/Mesa provides GBM, the greeter can be flipped back to Wayland with
# greeter-wayland.sh.
set -euo pipefail

echo "== Installing sddm =="
sudo pacman -S --needed --noconfirm sddm

echo "== Switching display manager: plasmalogin -> sddm =="
sudo systemctl disable plasmalogin.service
sudo systemctl enable sddm.service

echo "== Forcing SDDM greeter to X11 (avoids kwin_wayland/GBM entirely) =="
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-x11-nvidia.conf > /dev/null <<'EOF'
[General]
DisplayServer=x11
EOF

echo "== Done =="
echo "Reboot now. At the SDDM login screen, pick 'Plasma (X11)' from the"
echo "session dropdown before entering your password — SDDM remembers the"
echo "choice for next time. nvidia-drm.modeset=1 and the nouveau blacklist"
echo "are unchanged and still correct."
echo
echo "If the screen is ever black/broken again, recovery is unchanged: at the"
echo "Limine menu press 'e' and append:"
echo "  module_blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset"
