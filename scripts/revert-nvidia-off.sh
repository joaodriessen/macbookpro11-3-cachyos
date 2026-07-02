#!/usr/bin/env bash
# Undo nvidia-off.sh: re-enable the nvidia driver and rebuild the test UKI.
#
# ADAPT BEFORE RUNNING: KVER and the root= UUID are hardcoded for the machine
# this was developed on — set them to your own kernel version and root UUID.
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

KVER="7.1.2-3-cachyos"
UKI_PATH="/boot/EFI/Linux/igpu-test_linux-cachyos.efi"
MKINIT="/etc/mkinitcpio.conf"
BAK="${MKINIT}.bak-nvoff"
BL="/etc/modprobe.d/nvidia-blacklist.conf"

echo "==> Removing blacklist $BL"; rm -f "$BL"
echo "==> Restoring $MKINIT from $BAK"
[[ -e "$BAK" ]] && cp "$BAK" "$MKINIT" || echo "   (no backup found; leaving mkinitcpio.conf as-is)"
echo "    MODULES now: $(grep -E '^MODULES=' "$MKINIT")"

echo "==> Rebuilding test UKI with nvidia cmdline"
CMDLINE_FILE="$(mktemp)"; trap 'rm -f "$CMDLINE_FILE"' EXIT
printf '%s\n' 'nvidia-drm.modeset=1 nowatchdog rw rootflags=subvol=/@ root=UUID=0e1730ac-5ee7-41d8-a952-47b74da6a209' > "$CMDLINE_FILE"
mkinitcpio --kernel "$KVER" --uki "$UKI_PATH" --cmdline "$CMDLINE_FILE"
echo "Done. Reboot. (nvidia re-enabled; panel still on Intel unless you also run mux-to-nvidia.sh)"
