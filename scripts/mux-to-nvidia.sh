#!/usr/bin/env bash
# RECOVERY: return the internal panel to the NVIDIA dGPU.
# Deletes the gpu-power-prefs EFI var entirely -> firmware reverts to its default
# (dedicated/nvidia), which is the original known-good state (the var was absent
# before we started). Deletion is more reliable than rewriting, and does NOT
# depend on the buggy stock gpu-switch write path.
#
# Use over SSH if the panel is black after a mux flip, then: sudo reboot
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

EFIVAR="/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9"
mountpoint -q /sys/firmware/efi/efivars || mount -t efivarfs none /sys/firmware/efi/efivars

if [[ -e "$EFIVAR" ]]; then
  echo "==> Removing gpu-power-prefs (size $(stat -c%s "$EFIVAR") bytes)"
  chattr -i "$EFIVAR" 2>/dev/null || true
  rm -f "$EFIVAR"
  if [[ -e "$EFIVAR" ]]; then
    echo "Could not remove it. Fallback: write explicit dedicated (00) via dd:"
    printf '\x07\x00\x00\x00\x00\x00\x00\x00' | dd of="$EFIVAR" bs=8 count=1 conv=notrunc 2>/dev/null
    echo "   size now: $(stat -c%s "$EFIVAR")"
  else
    echo "Removed. Firmware will use its default (nvidia/dedicated) next boot."
  fi
else
  echo "gpu-power-prefs already absent — firmware default (nvidia) is in effect."
fi

echo
echo "Now reboot:  sudo reboot   (then pick your normal CachyOS entry)"
