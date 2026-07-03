#!/usr/bin/env bash
# Run AFTER rebooting with nvidia-off. Confirms nvidia is gone, Intel drives the
# panel, and shows the temperature drop. Read-only.
echo "===== nvidia modules (want NONE) ====="
lsmod | grep -i nvidia || echo "  no nvidia modules loaded"
echo
echo "===== nvidia PCI power state (want 'suspended' / D3) ====="
echo "  01:00.0 runtime_status: $(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null)"
echo "  01:00.0 power state:    $(cat /sys/bus/pci/devices/0000:01:00.0/power_state 2>/dev/null)"
echo
echo "===== desktop render path (want Intel) ====="
# Run from inside the graphical session if possible; DISPLAY=:0 is the
# fallback for SSH (reaches Xwayland/X11 on the console session).
{ glxinfo -B 2>/dev/null || DISPLAY=:0 glxinfo -B 2>/dev/null; } | grep -iE 'OpenGL renderer' \
  || echo "  (glxinfo unavailable — install mesa-utils, or run from the desktop session)"
echo
echo "===== panel connector (want eDP on INTEL card) ====="
for s in /sys/class/drm/card*-eDP-*/status; do
  d=$(dirname "$s"); real=$(readlink -f "$d")
  case "$real" in *00:02.0*) g=INTEL;; *01:00.0*) g=NVIDIA;; *) g="?";; esac
  echo "  $(basename "$d"): $(cat "$s") -> $g"
done
echo
echo "===== TEMPS (compare to your pre-nvoff baseline) ====="
sensors 2>/dev/null | grep -iE 'TG1D|TG0D|TC0P|TCXC|TCGC|fan' | head
echo
echo "===== fan RPM ====="
sensors 2>/dev/null | grep -iE 'fan'
