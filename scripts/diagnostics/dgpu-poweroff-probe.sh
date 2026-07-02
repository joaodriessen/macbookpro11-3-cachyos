#!/usr/bin/env bash
# Probe how to power the driverless NVIDIA dGPU down to D3 (the biggest remaining
# thermal win after nvidia-off.sh, since blacklisting the driver alone leaves the
# card powered even if idle). Tries the cheap lever (PCI runtime PM) live and
# reports the ACPI/acpi_call path.
#
# Investigated as part of the D3cold power-off question and ultimately abandoned:
# combined with decode-dsdt.sh, this confirmed there's no callable ACPI _OFF/_ON
# method for GFX0/P0P2 on this board (only a PSSR register save/restore method —
# see gfx0-acpi-excerpt.txt) — the only real path is a gmux-mediated cut via
# vga_switcheroo, which requires loading nouveau (flaky on this Kepler chip) to
# trigger it. Not worth it for the residual ~5C once nvidia-470xx is already
# blacklisted. Kept here as a reference for anyone who wants to dig further.
set -uo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi
D=/sys/bus/pci/devices/0000:01:00.0

echo "===== [1] current dGPU state ====="
echo "  driver:         $(basename "$(readlink -f $D/driver 2>/dev/null)" 2>/dev/null || echo none)"
echo "  power/control:  $(cat $D/power/control)"
echo "  runtime_status: $(cat $D/power/runtime_status)"
echo "  power_state:    $(cat $D/power_state)"

echo "===== [2] try PCI runtime PM (echo auto) — harmless, reversible ====="
echo auto > $D/power/control
sleep 3
echo "  after auto -> power_state: $(cat $D/power_state)  runtime_status: $(cat $D/power/runtime_status)"
echo "  (D3cold/D3hot = success; still D0 = PCI PM alone can't suspend it -> need acpi_call)"

echo "===== [3] is acpi_call available? ====="
if modinfo acpi_call >/dev/null 2>&1; then
  echo "  acpi_call module present: yes"
  modprobe acpi_call 2>&1 || true
  if [[ -e /proc/acpi/call ]]; then
    echo "  /proc/acpi/call ready — will scan candidate _OFF paths:"
    for P in '\_SB.PCI0.PEG0.PEGP._OFF' '\_SB.PCI0.PEGP.GFX0._OFF' '\_SB.PCI0.P0P2.PEGP._OFF' \
             '\_SB_.PCI0.PEG0.PEGP._OFF' '\_SB.PCI0.RP05.PEGP._OFF' '\_SB.PCI0.PEG0.PEGP.SGOF'; do
      echo -n "    try $P ... "
      echo "$P" > /proc/acpi/call 2>/dev/null
      r=$(cat /proc/acpi/call 2>/dev/null | tr -d '\0')
      echo "result: ${r:-<none>}"
      sleep 1
      echo "      dGPU power_state now: $(cat $D/power_state)"
    done
  else
    echo "  /proc/acpi/call missing after modprobe."
  fi
else
  echo "  acpi_call NOT installed. To use it: install acpi_call-dkms (AUR), then rerun this."
fi

echo "===== [4] DSDT candidate _OFF/_ON methods (if iasl present) ====="
if command -v acpidump >/dev/null && command -v iasl >/dev/null; then
  tmp=$(mktemp -d); (cd "$tmp" && acpidump -b >/dev/null 2>&1 && iasl -d dsdt.dat >/dev/null 2>&1 \
    && grep -nE 'PEGP|_OFF|_ON|Method.*_PS3|GFX0' dsdt.dsl | head -25); rm -rf "$tmp"
else
  echo "  (install acpica: 'pacman -S acpica' to decode DSDT and find the exact path)"
fi

echo "===== [5] temps now ====="
sensors 2>/dev/null | grep -iE 'TG1D|TG0D|TC0P' | head -3
