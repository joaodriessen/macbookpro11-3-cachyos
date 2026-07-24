#!/usr/bin/env bash
# Read-only: capture the Limine/UKI/mkinitcpio boot setup into a text report,
# useful for sanity-checking your bootloader/initramfs state before and after
# each migration step. Writes to $HOME by default — change OUT= as you like.
set -uo pipefail
if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi
OUT="${HOME}/boot-info.txt"
{
  echo "===== /etc/default/limine (non-comment) ====="
  grep -vE '^\s*#|^\s*$' /etc/default/limine 2>/dev/null || echo "(absent)"
  echo
  echo "===== /etc/mkinitcpio.conf MODULES + HOOKS ====="
  grep -E '^(MODULES|HOOKS)=' /etc/mkinitcpio.conf
  echo
  echo "===== mkinitcpio presets ====="
  ls -la /etc/mkinitcpio.d/ 2>/dev/null
  echo
  echo "===== /boot/EFI/Linux UKIs ====="
  ls -la /boot/EFI/Linux/ 2>/dev/null
  echo
  echo "===== regular initramfs images in /boot ====="
  ls -la /boot/*.img 2>/dev/null; ls -la /boot/initramfs* 2>/dev/null
  echo
  echo "===== /etc/kernel/cmdline (UKI cmdline source, if any) ====="
  cat /etc/kernel/cmdline 2>/dev/null || echo "(absent)"
  echo
  echo "===== limine.conf entries (names + protocols) ====="
  grep -nE '^/|comment|protocol|module_path|kernel_path|cmdline' /boot/limine.conf 2>/dev/null | head -60
  echo
  echo "===== nvidia blacklist file ====="
  cat /etc/modprobe.d/nvidia-blacklist.conf 2>/dev/null || echo "(absent)"
  echo
  echo "===== does regular initramfs still bundle nvidia? (lsinitcpio) ====="
  img=/boot/initramfs-linux-cachyos.img
  [[ -e "$img" ]] && lsinitcpio "$img" 2>/dev/null | grep -iE 'nvidia|i915' | head || echo "(image not found / lsinitcpio n/a)"
} > "$OUT" 2>&1
chmod 644 "$OUT"
echo "Wrote $OUT"
