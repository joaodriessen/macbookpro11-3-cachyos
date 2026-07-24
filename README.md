# MacBookPro11,3 — Intel-primary Linux (CachyOS + Limine)

This repo documents migrating a MacBookPro11,3 (Late 2013, Haswell) running
CachyOS Linux from its default NVIDIA-dGPU boot path to running entirely on
the Intel Iris Pro 5200 iGPU for the internal display and normal desktop,
without loading NVIDIA's legacy Kepler (`nvidia-470xx`) driver. The result is
a stable Wayland desktop, working hardware video decode/encode, and none of
the proprietary-driver instability described below.

Later testing corrected an important claim in the original documentation:
the driverless GT 750M is **not fully powered down** in production. Its
graphics and HDMI-audio functions remain in PCI D0. Isolated Nouveau tests
proved that selective OpenGL offload and automatic runtime suspend/wake are
possible, but also exposed an upstream Nouveau teardown bug that makes runtime
PM unsafe on Linux 7.1 and the installed 6.18 LTS kernel.

See [Hybrid GPU test results and safety gate](docs/hybrid-gpu-results.md) for
the measured Test 1/Test 2 results, root cause, current prohibition, Intel
acceleration audit, and exact prerequisites for a future Linux 7.2 retest.

## Hardware / software context

- **Machine**: MacBookPro11,3 (Late 2013 Retina), Haswell CPU.
- **GPUs**: Intel Iris Pro 5200 (integrated, GT3e) + NVIDIA GeForce GT 750M
  (Kepler, GK107M) as the discrete GPU, switched via Apple's `gmux` hardware
  mux. On Macs, Apple's firmware normally leaves the Intel iGPU
  **firmware-disabled** and boots everything through the NVIDIA GPU unless
  something tells the firmware "macOS is booting" (see below).
- **Distro**: CachyOS (Arch-based).
- **Bootloader**: Limine.
- **Kernel**: CachyOS kernel, 7.x series.
- **Desktop**: GNOME Wayland in the latest audit; KDE Plasma and Hyprland are
  also intentionally retained.

## Why: the problems being solved

`nvidia-470xx` is the newest legacy driver branch that still supports this
Kepler chip (GK107M) — NVIDIA dropped Kepler from all newer driver branches.
Running on it, even before touching anything else, causes three real
problems:

1. **No GBM support.** `nvidia-470xx` never got GBM (Generic Buffer
   Management) support. `kwin_wayland` requires GBM, so KWin's Wayland
   session simply won't come up on this driver. Worse: SDDM's `plasmalogin`
   greeter also renders through `kwin_wayland` unconditionally, so the
   *greeter itself* SIGSEGVs before you ever reach a session picker —
   regardless of which session you actually intend to log into. This is a
   non-obvious blocker: it looks like "the machine won't boot to a login
   screen at all," not "Wayland doesn't work." The fix at the time (see
   `scripts/fix-login-manager.sh`) was switching to SDDM with the greeter
   forced to X11, entirely bypassing `kwin_wayland`/GBM.
2. **Permanent max-clock heat and noise.** Once the PowerMizer registry
   setting gets pinned to "prefer maximum performance" (as it was on this
   machine, likely from an earlier troubleshooting attempt), the GT750M sits
   at full clocks even at idle — sustained ~70+ C and audible fan. See
   `scripts/fix-gpu-quickwin.sh` for the PowerMizer "adaptive" fix that was
   the first, partial mitigation, before the eventual full removal of nvidia.
3. **A buggy VA-API bridge.** The NVIDIA VA-API bridge on this driver/chip
   combination stalls video decode in Parsec and causes color-inversion bugs
   in Steam Link. This isn't a configuration problem — it's the bridge
   itself.

Taken together, the durable daily-driver fix was to stop using the proprietary
NVIDIA stack and make Intel the primary GPU. This does not electrically power
off the GT 750M, and it does not rule out future selective Nouveau/NVK offload
after the upstream safety fix is present.

## The final working architecture

1. **`apple_set_os` woken via a UKI (Unified Kernel Image).** The Linux
   kernel's own EFISTUB (`efi_main`) calls the Apple "Set OS" protocol before
   `ExitBootServices` when it detects a DMI match for supported Mac models
   (MacBookPro11,3 included) — this tells Apple's firmware "macOS is
   booting," which is what keeps the firmware-disabled Intel iGPU powered on.
   (Upstream kernel support for this EFISTUB `apple_set_os` call landed in
   July 2024.) Limine's native `protocol: linux` loading path bypasses the
   EFI stub entirely, so it never fires. The fix is to build the kernel as a
   UKI (`mkinitcpio --uki`, embedding kernel + initramfs + cmdline into one
   PE/EFI binary) and boot it via Limine's `protocol: efi`, which chainloads
   the UKI as a normal EFI application — running the stub, firing the
   `apple_set_os` call, pre-`ExitBootServices`. See
   `scripts/build-uki-igpu-test.sh` (isolated test entry) and
   `scripts/enable-uki-persist.sh` (converts the managed boot entries to UKIs
   so this happens on every normal boot, not just a manually-selected test
   entry).
2. **Panel muxed to Intel via the `gpu-power-prefs` EFI NVRAM variable.**
   This variable (GUID `fa4ce28d-b62f-4c99-9cc3-6815686e30f9`) is the same
   one macOS's own GPU-switching preference pane writes; setting it to
   "integrated" tells the gmux which GPU should drive the internal panel on
   the next boot. There's a real gotcha here: **efivarfs requires the 4-byte
   attributes + 4-byte data to land in a single `write()` syscall.** A shell
   `>` redirect (or naive `printf ... > file`) can split that into multiple
   writes, which silently stores a malformed, dataless (4-byte instead of
   8-byte) variable — this happened on the first attempt here. Interestingly,
   the well-known community `gpu-switch` tool (vendored in
   `scripts/gpu-switch.upstream`) uses exactly that `printf ... >` pattern
   internally, which is the same pattern that produced the corrupted
   variable on this machine/kernel. The fix used here
   (`scripts/mux-to-intel.sh`) writes the full 8 bytes through `dd` in one
   shot (`bs=8 count=1`), which is a single `write()` call and lands
   correctly — verified by checking the resulting file size is exactly 8
   bytes.
3. **nvidia + nouveau fully blacklisted from the initramfs, *and*
   intercepted via `install nvidia /bin/false`.** Plain `blacklist nvidia`
   in `modprobe.d` only stops *automatic* module loading triggered by udev/
   modalias matching — it does not stop an explicit `modprobe nvidia` call.
   Something in the KDE/Wayland (Plasma + SDDM Wayland greeter) startup path
   does call `modprobe nvidia` by name, which blacklist entries don't catch.
   The belt-and-suspenders fix is an `install nvidia /bin/false` override
   (and the equivalent for `nouveau`), which intercepts modprobe's handling
   of that module name entirely, regardless of how it was invoked. See
   `scripts/nvidia-off.sh`.
4. **`LIBVA_DRIVER_NAME=i965` pinned system-wide for VA-API H264
   decode/encode.** Haswell's GT3e (Iris Pro 5200) is only supported by the
   legacy `i965` VA-API driver — the newer `iHD` driver targets Broadwell and
   later. Without pinning this explicitly, some applications probe the wrong
   driver and hardware decode silently doesn't engage. See
   `scripts/setup-vaapi-i965.sh`.

## Why not X: two abandoned approaches

**(a) A third-party `apple_set_os` EFI shim interposed on Limine's boot
file.** Before landing on the UKI/EFISTUB approach above, a third-party EFI
shim that interposes on Limine's own boot binary (calling `apple_set_os`
itself, then chaining to Limine) was tried. This black-screened: the loader
hangs during its EFI-console print stage on this specific hardware, pre-
kernel, with no diagnosable logs to work from (nothing reaches `dmesg` or the
journal — the hang is before Linux is even loaded). Abandoned in favor of
using the kernel's own EFISTUB, which is a code path already exercised by
every normal `systemd-boot`/UKI user and needed no third-party shim at all.

**(b) Full dGPU D3cold power-off through ACPI alone.** After nvidia was
blacklisted, the GT750M remained driverless but electrically powered. The
first investigation asked whether ACPI alone could cut it to D3cold. This
meant decompiling the DSDT
(`scripts/diagnostics/decode-dsdt.sh`, `scripts/diagnostics/dgpu-poweroff-probe.sh`)
and searching every ACPI table for a callable power-off method on the
`GFX0`/`P0P2` devices. The finding (excerpted in
`scripts/gfx0-acpi-excerpt.txt`): there is no `_OFF`/`_ON`/`_PS3` method
anywhere in the GFX0 or P0P2 scope on this board — only a `PSSR` method,
which is a config-space register save/restore helper, not a power control
method.

Later isolated testing proved that Nouveau/vga_switcheroo runtime PM can move
the dGPU to PCI D3hot/`DynOff`, wake it for offload, and suspend it again. That
did **not** prove D3cold or a physical apple-gmux rail cut. The result is
functionally promising but is not safe to deploy because channel teardown
triggered the upstream Nouveau use-after-free documented in
[the hybrid results](docs/hybrid-gpu-results.md). Do not substitute manual
PCI/HDA unbinding or gmux writes; wait for the fixed kernel path.

## Trade-offs accepted

- **No external monitor support.** HDMI and the Thunderbolt/DisplayPort
  ports on this model are wired to the NVIDIA GPU only, not the Intel iGPU.
  With no NVIDIA graphics driver in production, external display output is
  unavailable. External-output testing remains a separate, mux-sensitive
  experiment after runtime PM is safe.
- **Older btrfs/Snapper snapshot entries could black-screen when booted
  directly.** The affected historical entries used Limine's `protocol:
  linux`, bypassed the UKI path and therefore never fired `apple_set_os`.
  Current snapshot entries use EFI-history UKIs, so that categorical warning
  no longer describes the installed configuration. After any bootloader or
  snapshot integration change, verify that the selected entry still boots a
  UKI containing the required firmware handoff before relying on it for
  recovery.

## Recovery story: SSH first, always

SSH access was the safety net for this entire migration. A black-screen
mid-migration — wrong mux state, a UKI that doesn't wake the iGPU, a
greeter that won't come up — is recoverable by SSH'ing in from another
device on the LAN and either running the matching revert script or writing
the mux variable back by hand. This is why `scripts/enable-ssh-recovery.sh`
is step zero, before anything else in this repo: **set up and verify SSH
access before you touch any mux, GPU, or firmware setting.** Every
destructive-looking script in `scripts/` has a paired revert/recovery
script for exactly this reason.

## Scripts

Everything in `scripts/` is reference material from the actual migration,
not a turnkey installer. These were written interactively, for this one
specific machine, and most have hardcoded values (kernel version strings,
this install's root filesystem UUID, `MacBookPro11,3` DMI checks) that you
should read and adapt before running anything. Read each script before
running it.

Roughly the order they were used in:

1. `enable-ssh-recovery.sh` — stand up SSH as the safety net. Do this first.
2. `build-uki-igpu-test.sh` / `verify-igpu.sh` — build an isolated test UKI
   and confirm the Intel iGPU wakes via `apple_set_os`, without touching any
   managed boot entry.
3. `install-gpu-switch.sh` / `gpu-switch.upstream` — install the vendored,
   community-known `gpu-switch` tool (third-party code, see below).
4. `mux-to-intel.sh` / `mux-to-nvidia.sh` / `verify-mux.sh` — flip the panel
   mux to Intel (via a single atomic `dd` write to the `gpu-power-prefs` EFI
   variable), verify it landed on the Intel card, and revert if needed.
5. `nvidia-off.sh` / `revert-nvidia-off.sh` / `verify-nvoff.sh` — blacklist
   and intercept the nvidia/nouveau modules, rebuild the initramfs/UKI, and
   verify nvidia is fully gone and temperatures dropped.
6. `enable-uki-persist.sh` — make the UKI/EFISTUB path permanent by
   converting the managed kernel boot entries themselves, so every normal
   boot (not just the test entry) wakes Intel.
7. `revert-uki-igpu-test.sh` — once the persistent path is confirmed
   working, clean up the standalone test entry.
8. `setup-vaapi-i965.sh` — pin the correct VA-API driver for hardware video
   decode/encode.
9. `greeter-wayland.sh` / `revert-greeter-wayland.sh` — capstone step, once
   nvidia is gone and Intel/Mesa provides GBM: flip the SDDM greeter itself
   to Wayland, proving the original GBM problem is solved.

Also included, from earlier in the same migration story (while still
running `nvidia-470xx`, before the decision to remove NVIDIA entirely):

- `fix-login-manager.sh` — the plasmalogin → SDDM/X11 fix for the
  `kwin_wayland`/GBM greeter crash described above.
- `fix-gpu-quickwin.sh` — the PowerMizer "adaptive" fix for the permanent
  max-clock heat/noise problem.

`scripts/diagnostics/` holds read-only investigation tools used along the
way (boot/mux state capture, ACPI table decoding, the D3cold power-off
probe) — useful if you're debugging the same kind of problem on your own
machine, not part of the "happy path."

`scripts/gfx0-acpi-excerpt.txt` is a short, hand-picked excerpt of the
decompiled ACPI tables relevant to the D3cold investigation above (not the
full 239KB DSDT dump).

### A note on `gpu-switch.upstream`

`scripts/gpu-switch.upstream` is vendored, unmodified, third-party code
(Copyright (c) 2014-2015 Bruno Bierbaumer, Andreas Heider, from
[0xbb/gpu-switch](https://github.com/0xbb/gpu-switch)). It is **not**
covered by this repo's MIT license — see the header comment in that file
and the note in `LICENSE`.

## Credits

This migration uses a community-known, previously-documented technique
rather than anything novel: EFISTUB `apple_set_os` support landed upstream
in the Linux kernel in July 2024, and the `gpu-power-prefs` EFI variable
technique has been documented via the `gpu-switch` tool and multiple
MacBookPro11,3 Linux users' writeups over the years. What this repo adds is
applying and debugging that known technique for one specific combination —
**CachyOS + Limine** specifically — where most existing guides assume GRUB
or rEFInd, plus the nvidia-off/VA-API/greeter fixes needed to get a stable,
quiet, Intel-primary desktop out of it on this hardware.
