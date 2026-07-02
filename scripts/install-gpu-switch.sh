#!/usr/bin/env bash
# Installs the vetted 0xbb/gpu-switch script to /usr/local/bin/gpu-switch so it
# is on $PATH (incl. over SSH) for switching AND recovery. Install only — does
# NOT switch anything. Source was fetched from github.com/0xbb/gpu-switch and
# reviewed; MacBookPro11,3 is in its tested-hardware list. It writes the EFI var
# gpu-power-prefs; nothing here writes it yet.
#
# See gpu-switch.upstream in this directory for the vendored script and its
# original copyright notice (Bruno Bierbaumer, Andreas Heider) — that file is
# third-party code, not covered by this repo's own MIT license.
set -euo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${HERE}/gpu-switch.upstream"
DST="/usr/local/bin/gpu-switch"
[[ -f "$SRC" ]] || { echo "ERROR: $SRC missing (the vetted upstream copy)."; exit 1; }

# Integrity: must be the reviewed script (writes the gpu-power-prefs efivar).
grep -q 'gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9' "$SRC" \
  || { echo "ERROR: $SRC does not look like gpu-switch (missing efivar GUID)."; exit 1; }

install -m755 "$SRC" "$DST"
echo "Installed -> $DST"
echo
echo "Sanity (prints usage, writes NOTHING):"
"$DST" --help
echo
echo "Ready. Switch command is now on PATH:  sudo gpu-switch --integrated"
echo "Recovery command (over SSH if needed):  sudo gpu-switch --dedicated"
