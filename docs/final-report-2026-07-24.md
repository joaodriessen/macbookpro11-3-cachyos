# CatchyBook Pro final improvement report

Audit and implementation period: 2026-07-22 through 2026-07-24.

This report closes the work that can be completed safely on the current
CachyOS installation. It distinguishes measured improvements from experiments
and records the external gates that must be cleared before GPU or suspend work
continues.

## Outcome

The MacBookPro11,3 is stable as an Intel-primary, always-plugged-in desktop:

- Intel i915 owns the internal panel and normal accelerated rendering.
- Intel i965 VA-API provides H.264 decode and encode.
- GNOME Wayland is current; KDE Plasma and Hyprland remain installed by
  choice.
- The standard in-kernel EEVDF scheduler is active. The local LAVD service is
  disabled but retained for rollback.
- Power Profiles Daemon remains balanced, which maps to Intel EPB 6 here.
- Lid close turns off the panel and lid open restores it without attempting
  the unsafe suspend path.
- SSH and Tailscale recovery remain enabled behind a default-deny firewall.
- SMART, Btrfs, memory pressure, zram and failed-unit checks are healthy.

The NVIDIA GT 750M is not claimed to be electrically off in production.
Nouveau remains unloaded because the tested runtime-PM path triggered an
upstream kernel use-after-free, and source inspection shows both installed
kernel lines contain the vulnerable teardown sequence.

## Measured before and after

| Area | Before | Final state |
|---|---|---|
| Root storage | Approximately 54 GiB used and 45 GiB free | Approximately 37 GiB used and 62 GiB available |
| PSD recovery accumulation | Three old copies totaling about 14.2 GiB nominally; later two experiment-period copies totaling 3.1 GiB | No recovery directories; `BACKUP_LIMIT=2` bounds the retained-copy count |
| Scheduler | Local LAVD 1.1.2 `--autopower` service active | EEVDF active; LAVD inactive/disabled but installed for rollback |
| Controlled scheduler throughput | LAVD mean 785,329.71 kB/s | EEVDF mean 830,681.91 kB/s, approximately 5.77% higher |
| Loaded wake tails | LAVD p95/p99: 91.0/102.1 µs and 94.5/112.1 µs | EEVDF p95/p99: 88.0/90.6 µs and 90.5/95.4 µs |
| Control-daemon policy | Ananicy placed thermald and PPD in `SCHED_IDLE`, nice 16, idle I/O | Both use `SCHED_OTHER`, nice 0, best-effort I/O priority 4 |
| HDA policy on AC | Powertop overrode CachyOS and left `snd_hda_intel power_save=1` | Ordered AC exception leaves `power_save=0`; PCI runtime policy remains `auto` |
| Chrome SSD protection | PSD active, default recovery retention of five | PSD remains active; retention explicitly limited to two |
| GPU documentation | Described an Intel-only machine and fully powered-down dGPU | Correctly documents Intel-primary D0 production and isolated hybrid results |

The scheduler temperature differences changed with test order, so no cooling
benefit is attributed to either scheduler. The final ten-minute EEVDF idle
confirmation averaged 4.45% CPU busy and 71.71°C package temperature with zero
new throttle events or time. That run is a steady-state safety check, not a
cross-day claim that EEVDF lowered temperature.

## Graphics verdict

Test 1 proved useful simultaneous operation:

- Intel retained the connected panel and default renderer.
- Nouveau bound the GK107M GT 750M.
- `DRI_PRIME=1` selected accelerated Mesa NVE7 OpenGL with 2 GiB VRAM.

Test 2 proved runtime D3hot/`DynOff`, wake-on-offload and return to suspend, but
failed the safety gate with a `refcount_t` underflow/use-after-free in the
Nouveau ABI16 scheduler teardown path.

Production therefore remains Intel-primary with Nouveau unloaded. Do not run
Test 2 on Linux 7.1.x or the installed 6.18 LTS kernel. A future retry requires:

1. A stable CachyOS kernel based on Linux 7.2 or later.
2. Direct source verification of upstream fixes `2f5f0563` and `cac96c8d`.
3. A coherent kernel/Mesa/NVK update rather than a partial graphics update.
4. A newly built isolated test UKI, preserved production recovery paths and
   one bounded wake/offload/idle cycle before broader testing.

The observed Starlight workload already uses Intel i965 VA-API, DRM PRIME and
EGL/GLES. Its recorded dropped frames were network loss, not evidence that
Intel decoding was disabled. Offloading it to the dGPU is unjustified without
a measured rendering bottleneck.

## Power, thermals and CachyOS tuning

- Keep PPD balanced/EPB 6. Performance and power-saver changed EPB to 0 and 15
  respectively but did not change governor, frequency limits or turbo.
- Keep EEVDF. Re-enable LAVD only as a rollback with
  `sudo systemctl enable --now scx_lavd.service`, then verify a `lavd_*`
  sched_ext root operation.
- Keep Ananicy, thermald, Powertop and the narrow Bluetooth/HDA exceptions.
  No additional blanket USB, PCI, Wi-Fi, SATA or Thunderbolt exception was
  justified by evidence.
- No physical cleaning or repaste was performed. The controlled workload
  showed responsive fans and zero new throttling in the completed two-worker
  scheduler runs; a rejected eight-worker workload reached 100°C, added 411
  throttle events/690 ms and must not be repeated.
- Further PPD or RAPL A/B work was stopped because its likely return did not
  justify more thermal testing.

### Host-specific rollback points

- LAVD: `sudo systemctl enable --now scx_lavd.service`, then verify that
  `/sys/kernel/sched_ext/root/ops` begins with `lavd_`.
- Ananicy control-daemon override: remove only
  `/etc/ananicy.d/99-local-control-daemons.rules` and
  `/etc/systemd/system/ananicy-cpp.service.d/20-control-daemon-priority.conf`,
  run `sudo systemctl daemon-reload`, then restart `ananicy-cpp.service`.
- AC HDA exception: disable and remove only
  `/etc/systemd/system/audio-no-powersave-on-ac.service`, then run
  `sudo systemctl daemon-reload`. The existing CachyOS/Powertop rules resume
  authority.
- PSD retention: remove or comment only `BACKUP_LIMIT=2` in
  `~/.config/psd/psd.conf` to restore PSD's default retention on its next
  normal start. Deleted recovery copies are separately recoverable from the
  recorded Restic snapshots, including `df56a346`.

## Suspend and lid behavior

Deep S3 is unsafe on this stack. A controlled RTC-alarmed test entered
`PM: suspend entry (deep)` but never recorded an exit and required forced power
recovery. A later attempted s2idle test raced and actually entered deep S3
again, so s2idle remains unproven; repeating either test is not justified now.

The accepted replacement is deliberately simpler:

- logind ignores lid-triggered suspend;
- `lid-display-off.service` blanks the gmux backlight on close;
- opening the lid restores the panel;
- the session and machine continue running.

## Storage and SSD

Conservative cleanup removed only confirmed rebuildable or recovery data:

- old Yay and Shelly build caches;
- three original PSD crash-recovery profiles;
- two later experiment-period PSD recovery profiles after verifying Restic
  snapshot `df56a346`.

Pacman rollback cache, Cargo, Flatpak, active PSD/Chrome data and all Starlight
source/build/cache paths were preserved. Weekly TRIM, monthly Btrfs scrub and
nightly Restic backup remain active. Final checks show SMART passed, zero
reallocated or pending sectors, zero interface errors, zero Btrfs device
errors and a clean latest scrub.

## Ten original verdicts

| # | Area | Final disposition |
|---|---|---|
| 1 | Hybrid graphics | OpenGL offload and runtime PM were proven; permanence is blocked by the upstream Nouveau bug |
| 2 | Thermals | Software stack audited and corrected narrowly; no physical service performed |
| 3 | Storage | Conservative cleanup completed; protected project/build data retained |
| 4 | Updates | Still deferred; no system, kernel, Mesa, Limine or DKMS upgrade performed |
| 5 | Background apps | Preserved; none disabled as an optimization |
| 6 | Desktop environments | GNOME, Plasma and Hyprland retained |
| 7 | PSD | Retained; recovery limit set to two and accumulated recoveries cleaned |
| 8 | Partitioning | Untouched |
| 9 | CachyOS tuning | Audited and measured; EEVDF selected, narrow Ananicy/HDA corrections retained |
| 10 | Kernel/LTS | Compared and preserved; default remains current CachyOS, future GPU retest waits for a source-verified fixed kernel |

## Final validation

On 2026-07-24:

- `verify-all.sh`: 17 pass, 0 warn, 0 fail.
- Failed system and user units: 0 and 0.
- Memory PSI: zero across current 10/60/300-second windows.
- Root Btrfs: 38% used after final cleanup; all device error counters zero.
- Latest Btrfs scrub: finished with no errors.
- SSD SMART: passed; 34,339 power-on hours; zero reallocated, pending or CRC
  errors.
- Current and LTS UKIs embed their installed kernels and retain their recorded
  safe BLAKE2b hashes.
- UFW: active, default-deny incoming; SSH admitted only from the home LAN and
  Tailscale ranges.
- Starlight development/build/cache paths and both active Chrome PSD backing
  paths: present.

## Intentionally deferred

The following are not unfinished chores; they are explicit gates:

- Nouveau runtime PM, NVK and external-output testing until the fixed coherent
  graphics stack is available.
- Any further deep-S3 or s2idle attempt without materially better early-resume
  diagnostics and a new evidence-led design.
- The parked custom kernel build.
- The unfinished PPD benchmark controller and its stash.
- Publishing the historical scheduler rerun controller; its current version
  does not restore an initially disabled LAVD state safely and should not run.
- System updates and partition changes until those verdicts are reversed.
