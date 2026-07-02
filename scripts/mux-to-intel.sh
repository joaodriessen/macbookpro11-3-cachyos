#!/usr/bin/env bash
# Flip the internal-panel mux hint to the Intel iGPU by writing the EFI var
# gpu-power-prefs = integrated. Robust for modern efivarfs: efivarfs requires
# the 4-byte attributes + data to arrive in ONE write() syscall, so we use dd
# (single write) instead of a shell '>' redirect (which can split the write and
# store a malformed, dataless variable — as happened on the first attempt, and
# as the upstream gpu-switch.upstream script in this directory still does via
# `printf ... >`, which is exactly the pattern that bit us here).
#
# Takes effect on NEXT boot. Reverse with:  sudo ./mux-to-nvidia.sh
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

EFIVAR="/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9"
# 8 bytes: attributes 07 00 00 00 (NV|BS|RT) + data 01 00 00 00 (1 = integrated/Intel)
BYTES='\x07\x00\x00\x00\x01\x00\x00\x00'

mountpoint -q /sys/firmware/efi/efivars || mount -t efivarfs none /sys/firmware/efi/efivars

echo "==> Clearing any existing (possibly malformed) gpu-power-prefs var"
if [[ -e "$EFIVAR" ]]; then
  echo "    current size: $(stat -c%s "$EFIVAR") bytes  (8 = good, 4 = malformed/empty)"
  chattr -i "$EFIVAR" 2>/dev/null || true
  rm -f "$EFIVAR" 2>/dev/null || true
fi

echo "==> Writing gpu-power-prefs = INTEGRATED (single 8-byte write via dd)"
printf "$BYTES" | dd of="$EFIVAR" bs=8 count=1 conv=notrunc 2>/dev/null

echo
echo "==> Verify: file size must be 8 (4 attr + 4 data)"
sz=$(stat -c%s "$EFIVAR" 2>/dev/null || echo 0)
echo "    size now: ${sz} bytes"
if [[ "$sz" == "8" ]]; then
  echo "    correct — 4-byte attributes + 4-byte data present."
else
  echo "    size is ${sz}, expected 8. Write did NOT land correctly."
  echo "       Do NOT reboot on this. Investigate before proceeding further."
  exit 1
fi
# Best-effort byte dump (gpu-power-prefs is often EINVAL on read even when valid — size is the real check)
echo "    (raw, may be unreadable/EINVAL which is fine): $(dd if="$EFIVAR" bs=8 count=1 2>/dev/null | od -An -tx1 || echo 'unreadable-EINVAL')"

echo
echo "============================================================================"
echo "MUX SET TO INTEL for next boot (size verified = 8 bytes). NOW:"
echo "  1. Confirm SSH from your other device is working — keep that device handy."
echo "  2. Reboot."
echo "  3. At the Limine menu pick:  \"iGPU Test (EFISTUB apple_set_os)\""
echo "  4. Watch the panel:"
echo "       * Lights up on Intel -> SUCCESS. Log in, run verify-mux.sh."
echo "       * Stays BLACK        -> SSH in and run:"
echo "             sudo ./mux-to-nvidia.sh && sudo reboot"
echo "============================================================================"
