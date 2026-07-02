#!/usr/bin/env bash
#
# Revert the Method #1 iGPU test: remove the standalone Limine entry and delete the
# test UKI. Touches ONLY the isolated test artifacts — your managed kernel entries,
# /etc/default/limine, Limine itself, and OpenCore are never involved.
#
# Run: sudo ./revert-uki-igpu-test.sh

set -euo pipefail

UKI_PATH="/boot/EFI/Linux/igpu-test_linux-cachyos.efi"

if (( EUID != 0 )); then
    echo "This script must run as root. Re-run: sudo $0" >&2
    exit 1
fi

echo "==> Removing the standalone top-level Limine EFI entry for the test UKI"
limine-entry-tool --remove-efi-path "$UKI_PATH" || echo "   (no matching entry, or already removed)"

echo "==> Deleting the test UKI file"
rm -f "$UKI_PATH"

echo
echo "DONE. Test entry and UKI removed. Your normal boot is exactly as before."
echo "(If you want, verify: 'ls /boot/EFI/Linux/' should not list igpu-test_*.efi.)"
