#!/usr/bin/env bash
# Intel i965 VA-API decode/encode setup: install vainfo, pin LIBVA_DRIVER_NAME=i965
# system-wide, report state. Haswell GT3e (Iris Pro 5200) is only supported by the
# legacy i965 VA-API driver, not the newer iHD driver (which targets Broadwell+),
# so this must be pinned explicitly or some apps will silently probe the wrong driver.
#
# Verification (vainfo) is run afterwards as the normal user in the graphical session.
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

echo "==> Installing libva-utils (vainfo)"
pacman -S --needed --noconfirm libva-utils

ENV=/etc/environment
echo "==> Pinning LIBVA_DRIVER_NAME=i965 in $ENV"
if grep -qE '^\s*LIBVA_DRIVER_NAME=' "$ENV" 2>/dev/null; then
  sed -i -E 's|^\s*LIBVA_DRIVER_NAME=.*|LIBVA_DRIVER_NAME=i965|' "$ENV"
else
  printf 'LIBVA_DRIVER_NAME=i965\n' >> "$ENV"
fi
grep -n 'LIBVA_DRIVER_NAME' "$ENV" | sed 's/^/   /'

echo
echo "Done. Now (as your normal user, NOT root) run:"
echo "    LIBVA_DRIVER_NAME=i965 vainfo 2>&1 | grep -iE 'Driver version|VAProfileH264|Entrypoint'"
echo "You want to see VAProfileH264* with VAEntrypointVLD (hardware decode)."
echo "(The system-wide pin takes effect on next login; the inline var tests it now.)"
