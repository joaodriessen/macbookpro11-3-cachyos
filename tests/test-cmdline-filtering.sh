#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scripts=(
  "$repo_root/scripts/build-uki-igpu-test.sh"
  "$repo_root/scripts/nvidia-off.sh"
  "$repo_root/scripts/revert-nvidia-off.sh"
)

for script in "${scripts[@]}"; do
  if ! grep -q 'gpu_test=\*|nouveau\.\*' "$script"; then
    echo "FAIL: $(basename "$script") does not strip inherited GPU-test/Nouveau parameters" >&2
    exit 1
  fi
done

echo "PASS: all UKI rebuild paths strip inherited GPU-test/Nouveau parameters"
