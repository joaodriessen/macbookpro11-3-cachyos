#!/usr/bin/env bash
# RECOVERY: put the SDDM greeter back on X11 by restoring the override file
# that greeter-wayland.sh disables.
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

OVR=/etc/sddm.conf.d/10-x11-nvidia.conf
DIS="${OVR}.disabled-wayland"

if [[ -f "$DIS" ]]; then
  mv "$DIS" "$OVR"
  echo "Restored X11 greeter override: $OVR"
else
  echo "No disabled override at $DIS — recreating a minimal X11 override."
  printf '[General]\nDisplayServer=x11\n' > "$OVR"
  echo "Wrote $OVR"
fi
echo "Run: sudo systemctl restart sddm   (or reboot) to apply."
