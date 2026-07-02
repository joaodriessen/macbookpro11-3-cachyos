#!/usr/bin/env bash
# Read-only diagnostic. Captures root-only mux/switcheroo/GPU state to a report.
# Touches nothing, changes nothing. Useful when a mux flip doesn't behave as
# expected and you need to see what the kernel actually thinks is going on.
set -u
OUT="${HOME:-/root}/diag-mux.out"
exec > "$OUT" 2>&1
chmod 644 "$OUT" 2>/dev/null

echo "===== date ====="; date

echo; echo "===== debugfs mounted? ====="
mount | grep -i debugfs || echo "(debugfs not mounted)"

echo; echo "===== /sys/kernel/debug/vgaswitcheroo/ contents ====="
ls -la /sys/kernel/debug/vgaswitcheroo/ 2>&1

echo; echo "===== vgaswitcheroo/switch (raw, showing empties) ====="
if [ -e /sys/kernel/debug/vgaswitcheroo/switch ]; then
  echo "[file exists]"
  wc -c < /sys/kernel/debug/vgaswitcheroo/switch
  cat -A /sys/kernel/debug/vgaswitcheroo/switch
else
  echo "(switch file does NOT exist)"
fi

echo; echo "===== dmesg: vga_switcheroo / gmux / apple / i915 / nvidia registration ====="
dmesg | grep -iE 'switcheroo|gmux|apple|i915|nvidia' | tail -60

echo; echo "===== DRM cards + connectors ====="
for c in /sys/class/drm/card[0-9]*; do
  [ -e "$c/dev" ] || continue
  echo "$c -> $(readlink -f $c)"
done
echo "--- connectors ---"
for c in /sys/class/drm/card*-*/status; do
  d=$(dirname "$c")
  echo "$(basename $d): status=$(cat $c 2>/dev/null) enabled=$(cat $d/enabled 2>/dev/null)"
done

echo; echo "===== PCI gfx drivers bound ====="
for pci in 0000:00:02.0 0000:01:00.0; do
  echo "$pci -> driver: $(basename $(readlink -f /sys/bus/pci/devices/$pci/driver 2>/dev/null) 2>/dev/null)  power/runtime_status: $(cat /sys/bus/pci/devices/$pci/power/runtime_status 2>/dev/null)"
done

echo; echo "===== apple_gmux info ====="
ls -la /sys/module/apple_gmux/ 2>/dev/null
dmesg | grep -i gmux

echo; echo "===== DONE ====="
