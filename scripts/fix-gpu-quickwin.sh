#!/usr/bin/env bash
# GPU quick-win fixes for MacBookPro11,3 (CachyOS, nvidia-470xx, Plasma X11), from
# BEFORE the full Intel-only migration — kept here as part of the migration history
# and because it documents the max-clocks/heat problem this project ultimately solved
# by removing nvidia-470xx entirely.
#
# Goal: undo the accidental "force MAXIMUM performance" PowerMizer pin (which had
#       been keeping the GT 750M at full clocks / ~73 C even at idle — nvidia-470xx
#       has no dynamic clock-gating story that behaves on this chip once mis-pinned),
#       return it to ADAPTIVE so it idles cool, and install decode-visibility tools
#       to diagnose Parsec / SteamLink decode failures with hard data.
# Review me before running. Run as your normal user; it will sudo where needed.
set -euo pipefail

echo "==> 1/4  Backing up current PowerMizer config"
sudo cp -a /etc/modprobe.d/nvidia-powermizer.conf \
           /etc/modprobe.d/nvidia-powermizer.conf.bak-maxperf 2>/dev/null || true

echo "==> 2/4  Replacing the max-perf pin with ADAPTIVE"
# Old (WRONG, = force maximum performance):
#   PerfLevelSrc=0x2222; PowerMizerDefaultAC=0x1; PowerMizerDefault=0x1
# New: let PowerMizer manage levels adaptively on both AC and battery.
printf 'options nvidia NVreg_RegistryDwords="PowerMizerEnable=0x1;PerfLevelSrc=0x3333;PowerMizerDefaultAC=0x3;PowerMizerDefault=0x3"\n' \
  | sudo tee /etc/modprobe.d/nvidia-powermizer.conf >/dev/null

echo "==> 3/4  Belt-and-suspenders: force adaptive at every X11 login too"
# This is the runtime lever that was proven to drop clocks to 270/419 MHz.
# Runs automatically for the Plasma X11 session via plasma-workspace/env.
mkdir -p "$HOME/.config/plasma-workspace/env"
cat > "$HOME/.config/plasma-workspace/env/nvidia-powermizer.sh" <<'EOF'
#!/bin/sh
# Force NVIDIA PowerMizer to Adaptive (cool idle) at session start.
nvidia-settings -a "[gpu:0]/GPUPowerMizerMode=0" >/dev/null 2>&1 || true
EOF
chmod +x "$HOME/.config/plasma-workspace/env/nvidia-powermizer.sh"

echo "==> 4/4  Installing decode-diagnostic tools (no effect on running system)"
sudo pacman -S --needed --noconfirm vdpauinfo libva-utils

echo "==> Rebuilding initramfs so the new modprobe option is embedded"
sudo mkinitcpio -P

echo
echo "DONE. Now REBOOT, then verify:"
echo "    nvidia-settings -q '[gpu:0]/GPUPowerMizerMode' -t      # want: 0"
echo "    nvidia-settings -q '[gpu:0]/GPUCurrentClockFreqs' -t   # want low idle e.g. 270,405"
echo "    sensors | grep -E 'TG1D|TG0D'                          # want well under 70 C idle"
echo "    vdpauinfo | grep -iA2 'H264'                           # confirm NVDEC H264 profiles"
echo "    LIBVA_DRIVER_NAME=nvidia vainfo                        # confirm VA-API/NVDEC entrypoints"
