#!/usr/bin/env bash
#
# Method #1 — wake the firmware-disabled Intel Iris Pro 5200 iGPU via the Linux
# kernel's own EFISTUB apple_set_os call.
#
# Mechanism: MacBookPro11,3 is in the kernel's DMI allow-list (apple_match_product_name),
# so when the kernel boots THROUGH its EFI stub (efi_main), the stub calls the Apple
# Set OS protocol before ExitBootServices, telling the firmware "macOS is booting" so
# it leaves the Intel GPU powered on. Limine's native `protocol: linux` bypasses the
# EFI stub, so we boot the kernel as a UKI (Unified Kernel Image) that Limine chainloads
# via `protocol: efi` — that runs the stub, which fires the set_os call.
#
# This is ISOLATED and REVERSIBLE:
#   * builds a UKI to its own file (does NOT touch your normal initramfs/vmlinuz)
#   * adds a STANDALONE top-level Limine menu entry (does NOT touch the managed
#     linux-cachyos / -lts / snapshot entries, /etc/default/limine, or OpenCore)
#   * your normal CachyOS entry stays the default -> recovery = reboot, pick it.
#
# ADAPT BEFORE RUNNING: KVER and the root= UUID below are hardcoded for the
# machine this was developed on. Set KVER to `uname -r` (or your target kernel)
# and root=UUID=... to your own root filesystem UUID (blkid).
#
# Run:  sudo ./build-uki-igpu-test.sh
# Revert: sudo ./revert-uki-igpu-test.sh

set -euo pipefail

KVER="7.1.2-3-cachyos"
KNAME="linux-cachyos"
UKI_DIR="/boot/EFI/Linux"
UKI_PATH="${UKI_DIR}/igpu-test_${KNAME}.efi"
ENTRY_NAME="iGPU Test (EFISTUB apple_set_os)"

if (( EUID != 0 )); then
    echo "This script must run as root (writes to the ESP /boot and edits Limine config)." >&2
    echo "Re-run: sudo $0" >&2
    exit 1
fi

# Sanity: right machine, right kernel, stub present.
prod="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown)"
[[ "$prod" == "MacBookPro11,3" ]] || { echo "WARNING: product_name is '$prod', expected MacBookPro11,3."; }
[[ -e "/usr/lib/modules/${KVER}/vmlinuz" ]] || { echo "ERROR: kernel image for ${KVER} not found."; exit 1; }
[[ -e "/usr/lib/systemd/boot/efi/linuxx64.efi.stub" ]] || { echo "ERROR: systemd EFI stub missing."; exit 1; }

# Diagnostic cmdline: identical to production MINUS 'quiet' and 'splash' so that, if
# the panel survives the EFI-stub stage, we can SEE boot output. apple_set_os is fired
# by the stub based on the DMI match, BEFORE the cmdline matters, so dropping quiet/splash
# does NOT change whether the iGPU wakes — it only makes a failure easier to diagnose.
CMDLINE_FILE="$(mktemp)"
trap 'rm -f "$CMDLINE_FILE"' EXIT
printf '%s\n' \
  'nvidia-drm.modeset=1 nowatchdog rw rootflags=subvol=/@ root=UUID=0e1730ac-5ee7-41d8-a952-47b74da6a209' \
  > "$CMDLINE_FILE"

echo "==> [1/3] Building UKI  ->  $UKI_PATH"
echo "    cmdline: $(cat "$CMDLINE_FILE")"
install -dm700 "$UKI_DIR"
mkinitcpio --kernel "$KVER" --uki "$UKI_PATH" --cmdline "$CMDLINE_FILE"

echo
echo "==> [2/3] Verifying the UKI is a valid EFI application"
ls -la "$UKI_PATH"
file "$UKI_PATH"
file "$UKI_PATH" | grep -q 'PE32+' || { echo "ERROR: not a PE/EFI binary."; exit 1; }

echo
echo "==> [3/3] Registering standalone top-level Limine entry: \"$ENTRY_NAME\""
echo "    (this does NOT alter your managed kernel entries)"
limine-entry-tool --add-efi "$ENTRY_NAME" "$UKI_PATH" \
    --comment "Method#1 EFISTUB apple_set_os iGPU test - safe to delete" \
    --overwrite

echo
echo "============================================================================"
echo "DONE. Next:"
echo "  1. Reboot."
echo "  2. At the Limine menu, select:  \"$ENTRY_NAME\""
echo "       (do NOT make it default; just pick it this once)"
echo "  3. If it boots to your desktop, open a terminal and run the verify script:"
echo "         ./verify-igpu.sh"
echo "     You want to see an Intel [8086:...] VGA/Display device appear in lspci."
echo
echo "RECOVERY: if the screen stays black after selecting the test entry, hold the"
echo "power button to force off, boot again, and pick your NORMAL CachyOS entry"
echo "(unchanged, still the default). Then run the revert script."
echo "============================================================================"
