#!/usr/bin/env bash
# Run AFTER booting with the mux flipped to Intel. Confirms the internal panel
# (eDP-1) is now driven by the Intel i915 card, not nvidia. Read-only.
echo "===== which card owns eDP-1 (want it on the i915/00:02.0 card) ====="
found=0
for e in /sys/class/drm/card*-eDP-1; do
  [ -e "$e" ] || continue
  found=1
  # NOTE: readlink the connector symlink ITSELF — its resolved path contains
  # the owning card's PCI address. (dirname would give /sys/class/drm, which
  # resolves to no PCI path and silently skips the INTEL/NVIDIA verdict.)
  real=$(readlink -f "$e")
  echo "$(basename "$e"): status=$(cat "$e/status" 2>/dev/null) enabled=$(cat "$e/enabled" 2>/dev/null)"
  echo "    path: $real"
  case "$real" in
    *0000:00:02.0*) echo "    -> ON INTEL i915" ;;
    *0000:01:00.0*) echo "    -> still on NVIDIA" ;;
    *)              echo "    -> UNRECOGNIZED PCI path (inspect above)" ;;
  esac
done
[ "$found" = 1 ] || echo "(no eDP-1 connector found at all — no working panel driver?)"
echo
echo "===== i915 eDP link state (want NO 'disabling eDP') ====="
# Prefer the journal: the dmesg ring buffer rotates on long uptimes (e.g.
# firewall log spam) and early-boot lines vanish from it.
( journalctl -b -k --no-pager 2>/dev/null || sudo dmesg 2>/dev/null || dmesg 2>/dev/null ) \
  | grep -iE 'i915.*(eDP|link|pipe|crtc)' | tail -15 \
  || echo "(no i915 eDP lines found — journal/dmesg may have rotated)"
echo
echo "===== i915 runtime status (want 'active' now that it drives the panel) ====="
cat /sys/bus/pci/devices/0000:00:02.0/power/runtime_status 2>/dev/null || echo "(no 00:02.0 — iGPU not awake?)"
echo
echo "===== gpu-power-prefs efivar ====="
# Three states you can see here:
#   8 bytes  = staged for next boot (07 00 00 00 | 01 00 00 00 = integrated)
#   absent   = NORMAL after a successful boot — the firmware consumes the
#              variable when it applies it. Absence + eDP on Intel = success.
#   4 bytes  = MALFORMED (attributes only, no data) — the split-write() bug;
#              rewrite it with mux-to-intel.sh before rebooting.
EFIVAR=/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9
if [ -e "$EFIVAR" ]; then
  sz=$(stat -c%s "$EFIVAR" 2>/dev/null || echo '?')
  echo "present, ${sz} bytes  (8 = staged ok, 4 = MALFORMED — rewrite before reboot)"
  od -An -tx1 "$EFIVAR" 2>/dev/null || echo "(contents unreadable / EINVAL — size is the real check)"
else
  echo "absent — normal after boot (firmware consumed it). The eDP check above is the ground truth."
fi
