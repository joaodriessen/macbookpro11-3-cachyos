#!/usr/bin/env bash
# Make Intel-only PERSISTENT: convert the managed kernel entries (linux-cachyos +
# -lts) to UKIs booted via Limine `protocol: efi`, so the kernel EFISTUB fires
# apple_set_os on EVERY normal boot (required to wake Intel — confirmed by testing
# that gpu-power-prefs=integrated alone, without the EFISTUB call, still black-screens).
#
# Leaves the standalone "iGPU Test" entry in place as a recovery fallback.
# Snapper snapshot entries stay protocol:linux (they will black-screen the panel
# if booted — SSH-recoverable; documented limitation, see README).
# Reversible: backup of /etc/default/limine at .bak-uki.
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

LIM=/etc/default/limine
BAK="${LIM}.bak-uki"

echo "==> [1/4] Backup $LIM -> $BAK"
[[ -e "$BAK" ]] || cp "$LIM" "$BAK"

echo "==> [2/4] Set ENABLE_UKI=yes"
if grep -qE '^\s*ENABLE_UKI=' "$LIM"; then
  sed -i -E 's/^\s*ENABLE_UKI=.*/ENABLE_UKI=yes/' "$LIM"
else
  printf '\nENABLE_UKI=yes\n' >> "$LIM"
fi
echo "   cmdline that UKIs will bake in:"; grep -n 'KERNEL_CMDLINE' "$LIM" | sed 's/^/     /'
echo "   ENABLE_UKI now: $(grep -E '^ENABLE_UKI=' "$LIM")"

echo "==> [3/4] Rebuild (builds per-kernel UKIs + registers protocol:efi entries)"
mkinitcpio -P
limine-update 2>/dev/null || true

echo "==> [4/4] VERIFY before reboot"
echo "-- UKIs now in /boot/EFI/Linux (want linux-cachyos.efi + -lts.efi) --"
ls -la /boot/EFI/Linux/ 2>/dev/null
echo "-- main kernel entry protocol (want 'efi') --"
awk '/Kernel version:/{f=1} f&&/protocol:/{print "   "$0; f=0}' /boot/limine.conf | head -1
echo "-- any managed entry still protocol: linux? (snapshots expected; main/lts should be efi) --"
grep -nE 'protocol: linux' /boot/limine.conf | head -5 || echo "   none"
echo "-- iGPU Test recovery entry still present? --"
grep -qi 'iGPU Test' /boot/limine.conf && echo "   present" || echo "   NOT in limine.conf — verify at the menu"
echo "-- cmdline of the new main UKI entry (should have quiet/splash, NO nvidia-drm) --"
awk '/Kernel version:/{f=1} f&&/cmdline:/{print "   "$0; f=0}' /boot/limine.conf | head -1

echo
echo "============================================================================"
echo "REBOOT. This time let it boot the DEFAULT top entry \"CachyOS\" (now a UKI)."
echo "  Expect: normal quiet/splash boot straight into Intel-only desktop, no"
echo "  need to pick the test entry anymore."
echo "After login run:  ./verify-mux.sh   (want eDP on INTEL, nvidia gone)"
echo
echo "RECOVERY if the default boots black: at the Limine menu pick \"iGPU Test\""
echo "  (still there), or SSH in and run ./mux-to-nvidia.sh"
echo "============================================================================"
