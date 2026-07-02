#!/usr/bin/env bash
# Run AFTER booting with the mux flipped to Intel. Confirms the internal panel
# (eDP-1) is now driven by the Intel i915 card, not nvidia. Read-only.
echo "===== which card owns eDP-1 (want it on the i915/00:02.0 card) ====="
for e in /sys/class/drm/card*-eDP-1; do
  [ -e "$e" ] || continue
  d=$(dirname "$e"); real=$(readlink -f "$d")
  echo "$(basename $d): status=$(cat $e/status 2>/dev/null) enabled=$(cat $d/enabled 2>/dev/null)"
  echo "    path: $real"
  case "$real" in
    *0000:00:02.0*) echo "    -> ON INTEL i915" ;;
    *0000:01:00.0*) echo "    -> still on NVIDIA" ;;
  esac
done
echo
echo "===== i915 eDP link state in dmesg (want NO 'disabling eDP') ====="
sudo dmesg 2>/dev/null | grep -iE 'i915.*(eDP|link|pipe|crtc)' | tail -15 || \
  dmesg 2>/dev/null | grep -iE 'i915.*(eDP|link|pipe|crtc)' | tail -15
echo
echo "===== i915 runtime status (want 'active' now that it drives the panel) ====="
cat /sys/bus/pci/devices/0000:00:02.0/power/runtime_status
echo
echo "===== gpu-power-prefs efivar (want 07 00 00 00 01 00 00 00) ====="
xxd /sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9 2>/dev/null || echo "(efivar unreadable without root)"
