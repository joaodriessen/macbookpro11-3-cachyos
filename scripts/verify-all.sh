#!/usr/bin/env bash
# verify-all.sh — one-shot, read-only health check of the ENTIRE Intel-primary
# architecture described in the README. Run it after the migration, after any
# kernel/limine/sddm update, or whenever something feels off:
#
#     sudo ./verify-all.sh
#
# It checks every load-bearing piece:
#   boot   : this boot went through the systemd EFI stub (=> apple_set_os fired),
#            ENABLE_UKI=yes, managed Limine entries are protocol: efi,
#            per-kernel UKIs exist and are NOT older than their kernels
#   gpu    : Intel iGPU visible on PCI, eDP panel owned by i915,
#            nvidia/nouveau not loaded, modprobe install-intercepts in place,
#            initramfs MODULES clean, dGPU driverless
#   mux    : gpu-power-prefs efivar state (absent = consumed by firmware = OK)
#   video  : LIBVA_DRIVER_NAME=i965 pinned, H264 hardware decode available
#   greeter: SDDM greeter on Wayland (no /etc X11 override)
#   safety : sshd recovery net enabled + active
#
# Exit code: 0 = no failures (warnings allowed), 1 = at least one FAIL.
set -uo pipefail

if (( EUID != 0 )); then echo "Run as root: sudo $0" >&2; exit 1; fi

PASS=0 WARN=0 FAIL=0
if [[ -t 1 ]]; then G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' B=$'\e[1m' N=$'\e[0m'; else G='' Y='' R='' B='' N=''; fi
pass() { echo "  ${G}PASS${N}  $*"; ((PASS++)); }
warn() { echo "  ${Y}WARN${N}  $*"; ((WARN++)); }
fail() { echo "  ${R}FAIL${N}  $*"; ((FAIL++)); }
info() { echo "  info  $*"; }
section() { echo; echo "${B}== $* ==${N}"; }

# Read a UTF-16LE string efivar (skipping the 4 attribute bytes).
efivar_str() {
  local f="/sys/firmware/efi/efivars/$1"
  [[ -e "$f" ]] || return 1
  tail -c +5 "$f" 2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null | tr -d '\0'
}

section "Machine"
prod=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo unknown)
if [[ "$prod" == "MacBookPro11,3" ]]; then pass "product: $prod"
else warn "product is '$prod' (this repo targets MacBookPro11,3 — checks may not apply)"; fi

section "Boot path (EFISTUB => apple_set_os)"
LOADER_GUID=4a67b082-0a4c-41cf-b6c7-440b29bb8c4f
if stub=$(efivar_str "StubInfo-${LOADER_GUID}"); then
  pass "this boot ran through the systemd EFI stub ($stub) — apple_set_os path exercised"
  img=$(efivar_str "StubImageIdentifier-${LOADER_GUID}" || true)
  [[ -n "$img" ]] && info "booted UKI: $img"
else
  fail "no StubInfo efivar — this boot did NOT go through the EFI stub (protocol: linux entry? apple_set_os never fired)"
fi

if grep -qE '^\s*ENABLE_UKI=yes' /etc/default/limine 2>/dev/null; then
  pass "ENABLE_UKI=yes in /etc/default/limine"
else
  fail "ENABLE_UKI is not 'yes' in /etc/default/limine — kernel updates will regenerate non-UKI entries"
fi

if [[ -r /boot/limine.conf ]]; then
  nonefi=$(grep -cE 'protocol:\s*linux' /boot/limine.conf || true)
  if (( nonefi == 0 )); then
    pass "every entry in limine.conf is protocol: efi (snapshots included)"
  else
    warn "$nonefi 'protocol: linux' entries in limine.conf — typically snapshots from BEFORE the UKI migration; booting one gives a black panel (SSH-recoverable). They age out as snapper prunes."
  fi
else
  warn "/boot/limine.conf unreadable — cannot check entry protocols"
fi

# Per-kernel UKI presence + content check: the .linux section embedded in the
# deployed UKI must be byte-identical to the installed kernel. (Do NOT trust
# mtimes here — the limine-mkinitcpio deploy step skips rewriting a UKI whose
# content is unchanged, so a perfectly-current UKI can carry an old mtime.)
mid=$(cat /etc/machine-id 2>/dev/null || true)
for moddir in /usr/lib/modules/*/; do
  kver=$(basename "$moddir")
  [[ -e "$moddir/vmlinuz" && -e "$moddir/pkgbase" ]] || continue
  kname=$(cat "$moddir/pkgbase")
  uki="/boot/EFI/Linux/${mid}_${kname}.efi"
  if [[ ! -e "$uki" ]]; then
    fail "no UKI for $kname ($kver) at $uki — run: mkinitcpio -P && limine-update"
  elif command -v objcopy >/dev/null; then
    tmpdir=$(mktemp -d)
    trap 'rm -f -- "$tmpdir/uki.efi" "$tmpdir/linux"; rmdir -- "$tmpdir"' EXIT
    if cp -- "$uki" "$tmpdir/uki.efi" &&
       objcopy -O binary --only-section=.linux "$tmpdir/uki.efi" "$tmpdir/linux" 2>/dev/null; then
      if cmp -s "$tmpdir/linux" "$moddir/vmlinuz"; then
        pass "UKI for $kname embeds exactly the installed kernel ($kver)"
      else
        fail "UKI for $kname does NOT contain the installed $kver kernel — stale UKI; run: mkinitcpio -P && limine-update"
      fi
    else
      fail "could not make and inspect an offline copy of the UKI for $kname ($kver)"
    fi
    rm -f -- "$tmpdir/uki.efi" "$tmpdir/linux"
    rmdir -- "$tmpdir"
    trap - EXIT
  else
    info "UKI for $kname present ($kver); objcopy (binutils) missing so embedded-kernel content not verified"
  fi
done

section "GPU state"
if lspci -nn | grep -qE '\[8086:[0-9a-f]+\].*(VGA|Display)|(VGA|Display).*\[8086:'; then
  pass "Intel iGPU visible on PCI (firmware left it powered on)"
else
  fail "no Intel VGA/Display device on PCI — iGPU did not wake (apple_set_os problem)"
fi

edp_ok=0; edp_seen=0
for e in /sys/class/drm/card*-eDP-1; do
  [[ -e "$e" ]] || continue
  edp_seen=1
  real=$(readlink -f "$e")
  case "$real" in
    *0000:00:02.0*) pass "panel $(basename "$e") is on Intel i915 (00:02.0), status=$(cat "$e/status" 2>/dev/null)"; edp_ok=1 ;;
    *0000:01:00.0*) fail "panel $(basename "$e") is still on the NVIDIA card (01:00.0)" ;;
    *)              warn "panel $(basename "$e") on unrecognized device: $real" ;;
  esac
done
(( edp_seen )) || fail "no eDP-1 connector exposed — no working panel driver"

if lsmod | grep -qE '^(nvidia|nouveau)'; then
  fail "nvidia/nouveau kernel modules are LOADED: $(lsmod | grep -oE '^(nvidia|nouveau)\w*' | tr '\n' ' ')"
else
  pass "no nvidia/nouveau modules loaded"
fi

if grep -rqsE '^\s*install\s+nvidia\s+/bin/false' /etc/modprobe.d/; then
  pass "modprobe 'install nvidia /bin/false' intercept present"
else
  warn "nvidia install-intercept missing in /etc/modprobe.d/ — an explicit 'modprobe nvidia' would not be blocked"
fi

mods=$(grep -E '^MODULES=' /etc/mkinitcpio.conf 2>/dev/null || echo '')
if [[ "$mods" == *nvidia* ]]; then fail "mkinitcpio still bundles nvidia: $mods"
elif [[ "$mods" == *i915* ]]; then pass "initramfs MODULES clean, i915 early-KMS in place: $mods"
else warn "i915 not in mkinitcpio MODULES ($mods) — early KMS not guaranteed"; fi

DGPU=/sys/bus/pci/devices/0000:01:00.0
if [[ -e "$DGPU" ]]; then
  if [[ -e "$DGPU/driver" ]]; then
    warn "dGPU has a driver bound: $(basename "$(readlink -f "$DGPU/driver")")"
  else
    pass "dGPU (GT750M) is driverless; power_state=$(cat "$DGPU/power_state" 2>/dev/null) (D0 is expected — no ACPI off-path on this board, see README)"
  fi
fi

section "Panel mux (gpu-power-prefs efivar)"
EFIVAR="/sys/firmware/efi/efivars/gpu-power-prefs-fa4ce28d-b62f-4c99-9cc3-6815686e30f9"
if [[ ! -e "$EFIVAR" ]]; then
  if (( edp_ok )); then pass "efivar absent — normal: firmware consumed it at boot; panel is on Intel"
  else warn "efivar absent AND panel not confirmed on Intel — stage it with mux-to-intel.sh before next boot"; fi
else
  sz=$(stat -c%s "$EFIVAR" 2>/dev/null || echo 0)
  case "$sz" in
    8) pass "efivar present, 8 bytes — correctly staged for next boot" ;;
    *) fail "efivar present but $sz bytes (want 8) — MALFORMED split-write; rewrite with mux-to-intel.sh before rebooting" ;;
  esac
fi

section "Hardware video decode (VA-API i965)"
if grep -qE '^\s*LIBVA_DRIVER_NAME=i965' /etc/environment 2>/dev/null; then
  pass "LIBVA_DRIVER_NAME=i965 pinned in /etc/environment"
else
  fail "LIBVA_DRIVER_NAME=i965 not pinned in /etc/environment — apps may probe the wrong driver (run setup-vaapi-i965.sh)"
fi
if command -v vainfo >/dev/null; then
  # --display drm works headless (no X/Wayland session needed).
  if LIBVA_DRIVER_NAME=i965 vainfo --display drm 2>/dev/null | grep -q 'VAProfileH264.*VLD'; then
    pass "i965 reports H264 hardware decode (VAProfileH264/VLD)"
  else
    warn "vainfo did not report H264/VLD via i965 — hardware decode may be broken"
  fi
else
  info "vainfo not installed (libva-utils) — skipping live decode probe"
fi

section "SDDM greeter"
x11_ovr=$(grep -lsE '^\s*DisplayServer\s*=\s*x11' /etc/sddm.conf.d/*.conf /etc/sddm.conf 2>/dev/null || true)
if [[ -n "$x11_ovr" ]]; then
  warn "greeter forced to X11 by: $x11_ovr (greeter-wayland.sh disables this once nvidia is gone)"
elif grep -qsE '^\s*DisplayServer\s*=\s*wayland' /usr/lib/sddm/sddm.conf.d/zz-wayland.conf; then
  pass "greeter on Wayland (distro zz-wayland.conf in effect, no /etc X11 override)"
else
  warn "could not confirm greeter DisplayServer — check: grep -rn DisplayServer /etc/sddm.conf.d /usr/lib/sddm/sddm.conf.d"
fi

section "Recovery net (SSH)"
if [[ "$(systemctl is-enabled sshd 2>/dev/null)" == enabled && "$(systemctl is-active sshd 2>/dev/null)" == active ]]; then
  pass "sshd enabled + active — black-screen recovery path available"
else
  warn "sshd not enabled+active — you'd have NO recovery path on a black screen (run enable-ssh-recovery.sh)"
fi

section "Thermals (informational)"
sensors 2>/dev/null | grep -iE 'TC0P|TCXC|TG0D|TG1D|fan' | sed 's/^/  /' || info "lm_sensors not available"

echo
echo "${B}== Summary: ${G}$PASS pass${N}${B}, ${Y}$WARN warn${N}${B}, ${R}$FAIL fail${N}${B} ==${N}"
(( FAIL == 0 )) || exit 1
exit 0
