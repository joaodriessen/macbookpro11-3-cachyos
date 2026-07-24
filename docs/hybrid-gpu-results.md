# Hybrid GPU test results and safety gate

This document records the observed Intel-primary/Nouveau hybrid-GPU results on
a MacBookPro11,3 and prevents an unsafe experiment from being repeated without
the upstream fix.

Runtime tests were performed on 2026-07-23. Kernel availability and the
installed configuration were re-audited on 2026-07-24; package availability
statements below describe that audit date.

## Production state

The stable daily boot uses the Intel Iris Pro P5200 for the internal panel and
normal rendering:

- i915 owns the connected eDP panel, DRM card and render node.
- Mesa reports direct-rendered Intel OpenGL.
- The legacy i965 VA-API driver provides Haswell H.264 decode and encode.
- Proprietary NVIDIA and Nouveau kernel modules remain unloaded.
- NVIDIA graphics `01:00.0` is unbound but remains PCI D0/runtime-active.
- NVIDIA HDMI audio `01:00.1` remains bound to `snd_hda_intel` and active.

The last two points correct the repository's original “fully powered down”
wording. Intel-primary production avoids the proprietary NVIDIA rendering
stack, but it does not cut power to the discrete GPU.

## Isolated test design

Two separate UKI/Limine entries were built without replacing the production
entry:

1. `GPU TEST 1 - SAFE BIND (Nouveau; AUTO-SLEEP OFF)` loads i915 and Nouveau
   with `nouveau.runpm=0`.
2. `GPU TEST 2 - POWER + WAKE (Nouveau; AUTO-SLEEP ON; RUN TEST 1 FIRST)`
   changes only runtime PM to `nouveau.runpm=1`.

Both preserve Intel panel ownership and block the proprietary NVIDIA modules.
Recovery SSH/Tailscale access and a manual return to the production entry were
required throughout.

The UKIs and their boot entries are machine-specific test artifacts, not
turnkey files for another installation.

## Test 1: bind-only OpenGL offload

Test 1 passed:

- Intel/i915 retained the connected internal panel and default renderer.
- Nouveau bound the GK107M GT 750M.
- vga_switcheroo registered the integrated GPU, discrete GPU and
  discrete-audio client.
- Proprietary NVIDIA modules stayed blocked.
- Normal `glxinfo -B` reported Intel.
- `DRI_PRIME=1 glxinfo -B` selected accelerated Mesa NVE7/GT 750M OpenGL with
  2 GiB VRAM.
- No Nouveau timeout, GPU fault, lockup or desktop failure was observed.
- The machine returned successfully to the normal production boot.

This proves selective OpenGL offload is possible while Intel continues driving
the desktop. It is not a power-saving mode: `nouveau.runpm=0` intentionally
keeps the discrete GPU awake.

## Test 2: runtime suspend and wake

Test 2 was functionally successful but failed the safety gate:

- Both NVIDIA functions reached runtime `suspended`.
- PCI reported D3hot and vga_switcheroo reported `DynOff`.
- An NVE7 offload request woke the graphics function.
- The graphics function returned to suspended/`DynOff` roughly ten seconds
  after the offload process exited.
- The Intel panel and default renderer remained usable.

During Nouveau channel teardown, however, the kernel emitted:

```text
refcount_t: underflow; use-after-free
```

The stack implicated `nouveau_sched_destroy`, with runtime suspend also in the
trace. The test was aborted and production was restored. No lockup occurred,
but a kernel use-after-free blocks repeated testing and permanent deployment.

## Root cause and fixed kernel requirement

The failing lifetime sequence is in the affected Nouveau ABI16 path,
`nouveau_abi16_chan_fini()`:

1. The vulnerable implementation calls `drm_sched_entity_fini()` directly.
2. It then calls `nouveau_sched_destroy()`.
3. Scheduler destruction reaches finalization again and decrements references
   twice.

Upstream fixed this with two commits:

- [`2f5f0563`](https://github.com/torvalds/linux/commit/2f5f05633e2229c8ec379e1d65151165c905671e)
  exports `drm_sched_entity_kill()`.
- [`cac96c8d`](https://github.com/torvalds/linux/commit/cac96c8d93faa073456fbb3a504b2a3d15d51841)
  replaces the first Nouveau finalization with that kill operation.

Direct source inspection established:

- Installed `7.1.3-2-cachyos`: vulnerable.
- Installed `6.18.38-2-cachyos-lts`: vulnerable.
- Upstream/CachyOS candidate Linux 7.1.4: still vulnerable; it retains the
  direct `drm_sched_entity_fini()` call and its changelog contains no backport.
- Linux 7.2 release candidates available at the time of the audit: fixed
  sequence present.

Do not infer safety from the version string alone. Before a future retry,
inspect the actual packaged kernel source and require both commit effects:

```bash
rg -n -C 3 'drm_sched_entity_kill' \
  drivers/gpu/drm/nouveau/nouveau_abi16.c
rg -n 'EXPORT_SYMBOL.*drm_sched_entity_kill' \
  drivers/gpu/drm/scheduler/sched_entity.c
```

The old `nouveau_abi16_chan_fini()` body must no longer call
`drm_sched_entity_fini()` directly.

## Current prohibition

Do **not**:

- boot Test 2 on Linux 7.1.x or the installed 6.18 LTS kernel;
- repeat the runtime-PM offload workload on those kernels;
- use LTS as a presumed workaround;
- force-unbind NVIDIA HDA or write manual PCI/gmux power controls;
- promote Test 1 to a daily boot merely because it binds successfully;
- install a mismatched Nouveau Vulkan package through a partial update.

Test 1 remains a bounded diagnostic option only. It is worthwhile for a known
OpenGL bottleneck, not as a generic desktop accelerator.

## Intel acceleration audit

The stable Intel path is already hardware accelerated:

- Direct-rendered Mesa OpenGL uses the Iris Pro P5200.
- i965 VA-API exposes H.264 decoding and encoding.
- The locally built Starlight Flatpak was observed opening Intel
  `renderD128`, decoding H.264 through i965 VA-API, exporting DRM PRIME
  surfaces and rendering through EGL/GLES on Wayland at 2880×1800/60.
- A short `intel_gpu_top` sample during that stream averaged approximately
  43.23% Video-engine and 32.45% Render/3D-engine use at about 3.76 W GPU
  power.

Starlight's observed CPU consumption was therefore not caused by a missing
hardware decoder. Its recorded dropped frames were network packet loss, not a
demonstrated Intel rendering bottleneck. Offloading this workload through
Nouveau would add cross-GPU/DMABUF complexity without a measured need.

## Future retest procedure

A new Test 2-style run is justified only after all of these gates pass:

1. A stable CachyOS kernel based on Linux 7.2 becomes available (none was
   available at the time of the 2026-07-24 audit).
2. The actual packaged source contains both scheduler-lifetime fixes above.
3. Kernel, Mesa, Intel Vulkan and optional `vulkan-nouveau` versions are
   updated coherently rather than partially.
4. Production UKI/Limine hashes and recovery access are revalidated.
5. A new isolated UKI is built for the fixed kernel; the old 7.1 Test 2 entry
   is not reused.
6. Intel panel/default rendering is verified before any offload request.
7. One bounded OpenGL wake/offload/idle cycle passes with no kernel warning.
8. Only then are repeated cycles, NVK and external-output tests considered,
   one variable at a time.

Until those conditions exist, the correct daily configuration is the current
Intel-primary production boot.
