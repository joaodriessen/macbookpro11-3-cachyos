#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sampler="$repo_root/scripts/thermal-sampler.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

"$sampler" --help | grep -q '^Usage:'

if "$sampler" --duration 0 --output "$workdir/invalid.csv" 2>/dev/null; then
  echo "duration 0 unexpectedly succeeded" >&2
  exit 1
fi

"$sampler" --duration 2 --interval 1 --output "$workdir/sample.csv"

expected='timestamp,elapsed_s,cpu_busy_pct,avg_freq_mhz,pkg_temp_c,fan_left_rpm,fan_right_rpm,load1,memory_psi_some_avg10,package_throttle_count,package_throttle_ms,scheduler,ppd_profile,ac_online'
actual=$(head -n 1 "$workdir/sample.csv")
[[ "$actual" == "$expected" ]]

rows=$(tail -n +2 "$workdir/sample.csv" | wc -l)
(( rows >= 2 ))

awk -F, '
  NR > 1 {
    if (NF != 14) exit 1
    if ($2 !~ /^[0-9]+$/) exit 1
    if ($3 !~ /^[0-9]+([.][0-9]+)?$/) exit 1
    if ($5 !~ /^[0-9]+([.][0-9]+)?$/) exit 1
    if ($6 !~ /^[0-9]+([.][0-9]+)?$/) exit 1
    if ($7 !~ /^[0-9]+([.][0-9]+)?$/) exit 1
  }
' "$workdir/sample.csv"

echo "thermal sampler tests passed ($rows samples)"
