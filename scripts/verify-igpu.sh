#!/usr/bin/env bash
#
# Run this AFTER booting the "iGPU Test (EFISTUB apple_set_os)" entry.
# It reports whether the Intel iGPU is now visible and whether the kernel EFI stub
# fired the Apple set_os call. No root needed for most of it.

echo "=================== iGPU wake verification ==================="
echo
echo "### 1. Which entry did we boot? (should be the UKI test entry, cmdline w/o 'quiet')"
cat /proc/cmdline
echo
echo "### 2. Intel GPU present in PCI?  (SUCCESS = an [8086:....] VGA/Display line here)"
if lspci -nn | grep -iE '\[8086:.*(VGA|Display|Iris|Graphics)\]|VGA.*8086|Display.*8086' ; then
    echo ">>> INTEL iGPU IS PRESENT — apple_set_os worked."
else
    echo ">>> No Intel VGA/Display device. Full GPU list:"
    lspci -nn | grep -iE 'VGA|Display|3D|8086:0d|10de:'
    echo ">>> If only the NVIDIA 10de: device shows, the iGPU did not wake."
fi
echo
echo "### 3. Kernel EFI-stub apple_set_os evidence (dmesg / journal)"
( journalctl -b -k 2>/dev/null || dmesg 2>/dev/null ) | grep -iE 'apple|set.?os|efi.?stub|dual.?gpu' | head -20 \
    || echo "   (no matching lines; message may be silent on this kernel)"
echo
echo "### 4. i915 driver bind status (only meaningful if Intel appeared)"
lspci -k -d 8086: 2>/dev/null | grep -A3 -iE 'VGA|Display' || echo "   (no Intel display device to bind)"
echo
echo "============================================================="
echo "If Intel appeared: move on to the mux + nvidia-off steps."
echo "If it did NOT: run ./revert-uki-igpu-test.sh and re-check your kernel/UKI setup."
echo "============================================================="
