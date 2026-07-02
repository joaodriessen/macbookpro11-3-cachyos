#!/usr/bin/env bash
# Capstone step, run AFTER nvidia is fully gone (see nvidia-off.sh): flip the SDDM
# GREETER itself to Wayland (kwin_wayland), now that Intel/Mesa provides GBM. This
# is a nice concrete proof that the GBM problem is solved — the same greeter that
# used to SIGSEGV under nvidia-470xx (see fix-login-manager.sh) now works.
#
# We do NOT add any new config: the distro already ships
# /usr/lib/sddm/sddm.conf.d/zz-wayland.conf (DisplayServer=wayland +
# CompositorCommand=kwin_wayland --drm ...). The ONLY thing forcing the greeter
# back to X11 is the nvidia-era override /etc/sddm.conf.d/10-x11-nvidia.conf
# (written by fix-login-manager.sh), which lives in /etc and therefore wins over
# /usr/lib. We just neutralize it by renaming it so it no longer ends in .conf
# (SDDM only reads *.conf). Fully reversible: revert-greeter-wayland.sh renames it back.
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

OVR=/etc/sddm.conf.d/10-x11-nvidia.conf
DIS="${OVR}.disabled-wayland"

echo "==> Current effective DisplayServer sources:"
grep -rn 'DisplayServer' /usr/lib/sddm/sddm.conf.d/ /etc/sddm.conf.d/ /etc/sddm.conf 2>/dev/null | sed 's/^/   /' || true

if [[ -f "$OVR" ]]; then
  echo "==> Disabling X11 override: $OVR -> $DIS"
  mv "$OVR" "$DIS"
else
  echo "==> $OVR not present (already disabled?) — nothing to move"
fi

echo "==> Distro Wayland greeter config that now takes effect:"
cat /usr/lib/sddm/sddm.conf.d/zz-wayland.conf | sed 's/^/   /'

echo
echo "==> New effective DisplayServer (want: only the /usr/lib wayland one):"
grep -rn 'DisplayServer' /usr/lib/sddm/sddm.conf.d/ /etc/sddm.conf.d/ /etc/sddm.conf 2>/dev/null | sed 's/^/   /' || true

echo
echo "============================================================================"
echo "Greeter set to Wayland. It takes effect at the NEXT reboot / SDDM restart."
echo "Safe test WITHOUT rebooting the desktop you're in:"
echo "  1) Save your work."
echo "  2) sudo systemctl restart sddm     # kills the current X session + greeter"
echo "     -> greeter should come back on Wayland (kwin_wayland)."
echo "  3) At the login screen, pick 'Plasma (Wayland)' from the session menu."
echo
echo "RECOVERY if the greeter fails to appear (black screen at boot):"
echo "  SSH in and run:"
echo "     sudo ./revert-greeter-wayland.sh && sudo systemctl restart sddm"
echo "  That restores the X11 greeter."
echo "============================================================================"
