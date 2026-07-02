#!/usr/bin/env bash
# nvidia-OFF: power down the GT 750M for good (heat + decode fix).
#   1. blacklist all nvidia modules
#   2. drop nvidia from initramfs MODULES=() and add i915 for early Intel KMS
#   3. rebuild the TEST UKI with a clean cmdline (no nvidia-drm.modeset=1)
# Then reboot into "iGPU Test (EFISTUB apple_set_os)" and validate Intel-only.
#
# NOTE: plain `blacklist nvidia` in modprobe.d is NOT sufficient by itself on
# a KDE/Wayland system — something in the Plasma/SDDM Wayland startup path
# calls `modprobe nvidia` explicitly by name, which blacklist entries don't
# stop (blacklist only prevents *automatic* module loading via udev aliases).
# The belt-and-suspenders fix that actually holds is an `install nvidia
# /bin/false` override — see the nvidia-blacklist.conf this script writes.
#
# REVERSIBLE: backups written; run revert-nvidia-off.sh to undo.
#
# ADAPT BEFORE RUNNING: KVER and the root= UUID are hardcoded for the machine
# this was developed on — set them to your own kernel version and root UUID.
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

KVER="7.1.2-3-cachyos"
UKI_PATH="/boot/EFI/Linux/igpu-test_linux-cachyos.efi"
MKINIT="/etc/mkinitcpio.conf"
BL="/etc/modprobe.d/nvidia-blacklist.conf"
BAK="${MKINIT}.bak-nvoff"

echo "==> [1/4] Backing up $MKINIT -> $BAK"
[[ -e "$BAK" ]] || cp "$MKINIT" "$BAK"
echo "    current: $(grep -E '^MODULES=' "$MKINIT")"

echo "==> [2/4] Removing nvidia from initramfs MODULES, adding i915 (early KMS)"
sed -i -E 's/^MODULES=\(.*\)/MODULES=(i915)/' "$MKINIT"
echo "    now:     $(grep -E '^MODULES=' "$MKINIT")"

echo "==> [3/4] Blacklisting nvidia modules -> $BL"
cat > "$BL" <<'EOF'
# Intel-iGPU-only mode: keep the NVIDIA GT 750M (GK107M) powered down.
# Fixes sustained max-clock heat and the Kepler video-decode/color bugs.
#
# blacklist alone stops *automatic* module loading via udev/modalias, but
# something in the KDE/Wayland (Plasma + SDDM Wayland greeter) startup path
# calls `modprobe nvidia` explicitly by name, which ignores blacklist. The
# `install ... /bin/false` line intercepts that explicit call too.
#
# To re-enable nvidia: delete this file, restore mkinitcpio.conf.bak-nvoff, rebuild.
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nouveau
install nvidia /bin/false
install nouveau /bin/false
EOF
cat "$BL"

echo "==> [4/4] Rebuilding TEST UKI (clean cmdline, no nvidia-drm.modeset=1)"
CMDLINE_FILE="$(mktemp)"; trap 'rm -f "$CMDLINE_FILE"' EXIT
printf '%s\n' 'nowatchdog rw rootflags=subvol=/@ root=UUID=0e1730ac-5ee7-41d8-a952-47b74da6a209' > "$CMDLINE_FILE"
echo "    cmdline: $(cat "$CMDLINE_FILE")"
mkinitcpio --kernel "$KVER" --uki "$UKI_PATH" --cmdline "$CMDLINE_FILE"
file "$UKI_PATH" | grep -q 'PE32+' || { echo "ERROR: UKI not a valid EFI binary"; exit 1; }

echo
echo "============================================================================"
echo "nvidia-OFF staged. NOW:"
echo "  1. Keep your SSH device handy."
echo "  2. Reboot, pick \"iGPU Test (EFISTUB apple_set_os)\"."
echo "  3. Expect: desktop on Intel as before, but nvidia GONE and temps dropping."
echo "     Verify:  ./verify-nvoff.sh"
echo
echo "RECOVERY if boot/desktop breaks: ssh in and run"
echo "     sudo ./revert-nvidia-off.sh && sudo reboot"
echo "  (the panel stays on Intel regardless, so a black screen from this step is unlikely)"
echo "============================================================================"
