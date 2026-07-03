#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/verify-all.sh"

if ! grep -q 'cp -- "$uki" "$tmpdir/uki.efi"' "$script"; then
  echo "FAIL: verify-all.sh must copy each live UKI before inspection" >&2
  exit 1
fi

if ! grep -q 'objcopy -O binary --only-section=.linux "$tmpdir/uki.efi"' "$script"; then
  echo "FAIL: objcopy must inspect the offline UKI copy" >&2
  exit 1
fi

if grep -q 'objcopy -O binary --only-section=.linux "$uki"' "$script"; then
  echo "FAIL: objcopy still receives a live UKI path" >&2
  exit 1
fi

echo "PASS: verify-all.sh inspects only an offline UKI copy"
