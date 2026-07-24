#!/usr/bin/env bash
# Undo nvidia-off.sh: re-enable the nvidia driver and rebuild the test UKI.
#
# KVER and the cmdline are AUTO-DETECTED from the running system; review what
# the script prints. Override via env: KVER=... CMDLINE=... sudo -E $0
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

KVER="${KVER:-$(uname -r)}"
KNAME="$(cat "/usr/lib/modules/${KVER}/pkgbase" 2>/dev/null || echo linux)"
UKI_PATH="/boot/EFI/Linux/igpu-test_${KNAME}.efi"
MKINIT="/etc/mkinitcpio.conf"
BAK="${MKINIT}.bak-nvoff"
BL="/etc/modprobe.d/nvidia-blacklist.conf"

echo "==> Removing blacklist $BL"; rm -f "$BL"
echo "==> Restoring $MKINIT from $BAK"
[[ -e "$BAK" ]] && cp "$BAK" "$MKINIT" || echo "   (no backup found; leaving mkinitcpio.conf as-is)"
echo "    MODULES now: $(grep -E '^MODULES=' "$MKINIT")"

echo "==> Rebuilding test UKI with nvidia cmdline"
# Default: current boot's cmdline minus quiet/splash and bootloader noise, with
# nvidia-drm.modeset=1 re-added (nvidia-off.sh strips every nvidia-* param).
if [[ -z "${CMDLINE:-}" ]]; then
  keep=()
  # shellcheck disable=SC2013  # word-splitting the cmdline is the point here
  for arg in $(cat /proc/cmdline); do
    case "$arg" in
      quiet|splash|BOOT_IMAGE=*|initrd=*|nvidia*|gpu_test=*|nouveau.*) ;;
      *) keep+=("$arg") ;;
    esac
  done
  CMDLINE="nvidia-drm.modeset=1 ${keep[*]}"
fi
if [[ "$CMDLINE" != *root=* ]]; then
  CMDLINE+=" rw rootflags=subvol=$(findmnt -no FSROOT /) root=UUID=$(findmnt -no UUID /)"
  echo "    NOTE: no root= in /proc/cmdline; derived from findmnt instead."
fi
CMDLINE_FILE="$(mktemp)"; trap 'rm -f "$CMDLINE_FILE"' EXIT
printf '%s\n' "$CMDLINE" > "$CMDLINE_FILE"
echo "    kernel:  $KVER ($KNAME)"
echo "    cmdline: $CMDLINE"
mkinitcpio --kernel "$KVER" --uki "$UKI_PATH" --cmdline "$CMDLINE_FILE"
echo "Done. Reboot. (nvidia re-enabled; panel still on Intel unless you also run mux-to-nvidia.sh)"
