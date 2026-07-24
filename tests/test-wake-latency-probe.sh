#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/tools/wake-latency-probe.c"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
binary="$workdir/wake-latency-probe"
output="$workdir/latency.csv"

cc -std=c17 -O2 -Wall -Wextra -Werror -pedantic "$source_file" -o "$binary"

"$binary" --help | grep -q '^Usage:'

if "$binary" --duration 0 --output "$output" 2>/dev/null; then
  echo "duration 0 unexpectedly succeeded" >&2
  exit 1
fi

if "$binary" --duration 1 --interval-ms 700 --output "$output" 2>/dev/null; then
  echo "non-divisible interval unexpectedly succeeded" >&2
  exit 1
fi

printf 'preserve-me\n' > "$output"
if "$binary" --duration 1 --output "$output" 2>/dev/null; then
  echo "existing output path unexpectedly succeeded" >&2
  exit 1
fi
[[ $(<"$output") == preserve-me ]]
rm "$output"

"$binary" --duration 1 --interval-ms 10 --output "$output"

[[ $(head -n 1 "$output") == 'sample,elapsed_ms,latency_us' ]]

rows=$(tail -n +2 "$output" | wc -l)
(( rows >= 95 && rows <= 105 ))

awk -F, '
  NR > 1 {
    if (NF != 3) exit 1
    if ($1 !~ /^[0-9]+$/) exit 1
    if ($2 !~ /^[0-9]+([.][0-9]+)?$/) exit 1
    if ($3 !~ /^[0-9]+([.][0-9]+)?$/) exit 1
    if ($2 <= previous) exit 1
    previous=$2
  }
' "$output"

echo "wake latency probe tests passed ($rows samples)"
