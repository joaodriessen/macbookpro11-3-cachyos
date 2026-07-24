#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: thermal-sampler.sh --duration SECONDS --output FILE [--interval SECONDS]

Record read-only CPU, thermal, fan, pressure, throttle, scheduler, and power
profile telemetry as CSV. Duration and interval must be positive integers.
This MacBook-specific sampler requires x86_pkg_temp, applesmc fan sensors,
and /sys/class/power_supply/macsmc-ac/online. Existing output is never replaced.
EOF
}

duration=
interval=1
output=

while (($#)); do
  case "$1" in
    --duration)
      duration=${2-}
      shift 2
      ;;
    --interval)
      interval=${2-}
      shift 2
      ;;
    --output)
      output=${2-}
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! $duration =~ ^[1-9][0-9]*$ ]]; then
  echo "--duration must be a positive integer" >&2
  exit 2
fi
if [[ ! $interval =~ ^[1-9][0-9]*$ ]]; then
  echo "--interval must be a positive integer" >&2
  exit 2
fi
if [[ -z $output ]]; then
  echo "--output is required" >&2
  exit 2
fi
if [[ ! -d $(dirname "$output") ]]; then
  echo "Output directory does not exist: $(dirname "$output")" >&2
  exit 2
fi
if [[ -e $output || -L $output ]]; then
  echo "Refusing existing output path: $output" >&2
  exit 2
fi
if ! command -v sensors >/dev/null; then
  echo "sensors is required" >&2
  exit 2
fi

pkg_temp_path=
for zone in /sys/class/thermal/thermal_zone*; do
  if [[ -r $zone/type && $(<"$zone/type") == x86_pkg_temp ]]; then
    pkg_temp_path=$zone/temp
    break
  fi
done
if [[ -z $pkg_temp_path || ! -r $pkg_temp_path ]]; then
  echo "x86_pkg_temp thermal zone is unavailable" >&2
  exit 2
fi

read_cpu_times() {
  local user nice system idle iowait irq softirq steal rest
  read -r _ user nice system idle iowait irq softirq steal rest < /proc/stat
  CPU_IDLE=$((idle + iowait))
  CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
}

average_frequency_mhz() {
  awk '{ total += $1; count++ } END {
    if (count) printf "%.1f", total / count / 1000
    else printf "0.0"
  }' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
}

fan_speeds() {
  sensors -u applesmc-isa-0300 2>/dev/null |
    awk '
      /fan1_input:/ { left=$2 }
      /fan2_input:/ { right=$2 }
      END {
        if (left == "") left="unknown"
        if (right == "") right="unknown"
        printf "%s %s\n", left, right
      }
    '
}

max_throttle_value() {
  local pattern=$1
  awk 'BEGIN { max=0 } { if ($1 > max) max=$1 } END { print max }' \
    /sys/devices/system/cpu/cpu*/thermal_throttle/"$pattern" 2>/dev/null
}

read -r initial_fan_left initial_fan_right < <(fan_speeds)
if [[ $initial_fan_left == unknown || $initial_fan_right == unknown ]]; then
  echo "Both applesmc fan sensors are required" >&2
  exit 2
fi
ac_online_path=/sys/class/power_supply/macsmc-ac/online
if [[ ! -r $ac_online_path ]]; then
  echo "AC state is unavailable at $ac_online_path" >&2
  exit 2
fi

set -o noclobber
printf '%s\n' \
  'timestamp,elapsed_s,cpu_busy_pct,avg_freq_mhz,pkg_temp_c,fan_left_rpm,fan_right_rpm,load1,memory_psi_some_avg10,package_throttle_count,package_throttle_ms,scheduler,ppd_profile,ac_online' \
  > "$output"

read_cpu_times
previous_idle=$CPU_IDLE
previous_total=$CPU_TOTAL
elapsed=0

while ((elapsed < duration)); do
  sleep_for=$interval
  if ((elapsed + sleep_for > duration)); then
    sleep_for=$((duration - elapsed))
  fi
  sleep "$sleep_for"
  elapsed=$((elapsed + sleep_for))

  read_cpu_times
  delta_idle=$((CPU_IDLE - previous_idle))
  delta_total=$((CPU_TOTAL - previous_total))
  previous_idle=$CPU_IDLE
  previous_total=$CPU_TOTAL
  cpu_busy=$(awk -v total="$delta_total" -v idle="$delta_idle" \
    'BEGIN { if (total > 0) printf "%.1f", 100 * (total-idle) / total; else printf "0.0" }')

  avg_freq=$(average_frequency_mhz)
  pkg_temp=$(awk '{ printf "%.1f", $1 / 1000 }' "$pkg_temp_path")
  read -r fan_left fan_right < <(fan_speeds)
  load1=$(awk '{ print $1 }' /proc/loadavg)
  memory_psi=$(awk -F'[ =]' '/^some / { print $3 }' /proc/pressure/memory)
  throttle_count=$(max_throttle_value package_throttle_count)
  throttle_ms=$(max_throttle_value package_throttle_total_time_ms)
  scheduler=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || printf 'eevdf')
  [[ -n $scheduler ]] || scheduler=eevdf
  ppd_profile=$(powerprofilesctl get 2>/dev/null || printf 'unknown')
  ac_online=$(<"$ac_online_path")

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date --iso-8601=seconds)" "$elapsed" "$cpu_busy" "$avg_freq" \
    "$pkg_temp" "$fan_left" "$fan_right" "$load1" "$memory_psi" \
    "$throttle_count" "$throttle_ms" "$scheduler" "$ppd_profile" "$ac_online" \
    >> "$output"
done

printf 'Wrote %s samples to %s\n' "$(tail -n +2 "$output" | wc -l)" "$output"
