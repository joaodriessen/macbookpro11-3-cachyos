#!/usr/bin/env bash
# Decode the DSDT (root needed to read ACPI tables) and extract the dGPU
# power-off method + its full ACPI namespace path. Writes a readable report.
# This is the tool that was used to determine there is NO callable ACPI
# power-off path for the dGPU on this board — see gfx0-acpi-excerpt.txt and
# the README's "why not D3cold" section for what it found.
set -uo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi
OUT="${HOME:-/root}/dsdt-gpu.txt"
if ! command -v acpidump >/dev/null || ! command -v iasl >/dev/null; then
  echo "ERROR: acpidump/iasl missing — install acpica: pacman -S acpica" >&2; exit 1
fi
W=$(mktemp -d)
trap 'cd /; rm -rf "$W"' EXIT
cd "$W" || exit 1
acpidump -b >/dev/null 2>&1
iasl -d dsdt.dat >/dev/null 2>&1
[[ -s dsdt.dsl ]] || { echo "ERROR: DSDT decompile produced no dsdt.dsl — check acpidump/iasl output by hand." >&2; exit 1; }
{
  echo "=== Device(PEGP) / GFX0 blocks and _OFF/_ON/_PS3 methods with line numbers ==="
  grep -nE 'Device \(PEGP\)|Device \(GFX0\)|Device \(PEG0\)|Device \(P0P2\)|Device \(RP0[0-9]\)|Method \(_OFF|Method \(_ON|Method \(_PS3|Method \(_PS0|Method \(SGOF|Method \(SGON|Name \(_ADR' dsdt.dsl 2>/dev/null | head -80
  echo
  echo "=== Context: 3 lines around every PEGP occurrence ==="
  grep -nE -B1 -A2 'PEGP' dsdt.dsl 2>/dev/null | head -60
  echo
  echo "=== Any Scope(\\_SB...) wrappers to reconstruct full path ==="
  grep -nE 'Scope \(|Device \(PCI0\)|Device \(PEG' dsdt.dsl 2>/dev/null | head -40
} > "$OUT" 2>&1
chmod 644 "$OUT"
echo "Wrote $OUT ($(wc -l < "$OUT") lines)."
