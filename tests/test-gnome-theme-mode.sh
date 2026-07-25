#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
theme_tool="$repo_root/scripts/gnome-theme-mode.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

mkdir -p "$workdir/bin"
printf '%s\n' 'prefer-dark' > "$workdir/color-scheme"
printf '%s\n' 'disabled' > "$workdir/light-style"
printf '%s\n' '2' > "$workdir/panel-style"
printf '%s\n' '2' > "$workdir/dock-style"
: > "$workdir/gsettings.log"
: > "$workdir/extensions.log"

cat > "$workdir/bin/gsettings" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --schemadir ]]; then
  shift 2
fi

command=${1:-}
schema=${2:-}
key=${3:-}
value=${4:-}

case "$schema $key" in
  "org.gnome.desktop.interface color-scheme")
    state_file="$MOCK_STATE_DIR/color-scheme"
    ;;
  "org.gnome.shell.extensions.blur-my-shell.panel style-panel")
    state_file="$MOCK_STATE_DIR/panel-style"
    ;;
  "org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock")
    state_file="$MOCK_STATE_DIR/dock-style"
    ;;
  *)
    echo "unexpected gsettings target: $schema $key" >&2
    exit 91
    ;;
esac

case "$command" in
  get)
    current=$(<"$state_file")
    if [[ $key == color-scheme ]]; then
      printf "'%s'\n" "$current"
    else
      printf '%s\n' "$current"
    fi
    ;;
  set)
    value=${value//\'/}
    printf 'set %s %s %s\n' "$schema" "$key" "$value" >> "$MOCK_STATE_DIR/gsettings.log"
    printf '%s\n' "$value" > "$state_file"
    ;;
  *)
    echo "unexpected gsettings command: $command" >&2
    exit 92
    ;;
esac
MOCK

cat > "$workdir/bin/gnome-extensions" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

command=${1:-}
uuid=${2:-}
expected_uuid=light-style@gnome-shell-extensions.gcampax.github.com
[[ $uuid == "$expected_uuid" ]] || {
  echo "unexpected extension UUID: $uuid" >&2
  exit 93
}

case "$command" in
  info)
    if [[ $(<"$MOCK_STATE_DIR/light-style") == enabled ]]; then
      printf '%s\n' 'State: ENABLED'
    else
      printf '%s\n' 'State: DISABLED'
    fi
    ;;
  enable)
    [[ ${MOCK_FAIL_EXTENSION:-} != enable ]] || exit 94
    printf '%s\n' enable >> "$MOCK_STATE_DIR/extensions.log"
    printf '%s\n' enabled > "$MOCK_STATE_DIR/light-style"
    ;;
  disable)
    [[ ${MOCK_FAIL_EXTENSION:-} != disable ]] || exit 95
    printf '%s\n' disable >> "$MOCK_STATE_DIR/extensions.log"
    printf '%s\n' disabled > "$MOCK_STATE_DIR/light-style"
    ;;
  *)
    echo "unexpected gnome-extensions command: $command" >&2
    exit 96
    ;;
esac
MOCK

chmod +x "$workdir/bin/gsettings" "$workdir/bin/gnome-extensions"
export MOCK_STATE_DIR="$workdir"
export PATH="$workdir/bin:$PATH"
export BMS_SCHEMA_DIR="$workdir/fake-bms-schemas"

"$theme_tool" light
grep -qx 'prefer-light' "$workdir/color-scheme"
grep -qx 'enabled' "$workdir/light-style"
grep -qx '1' "$workdir/panel-style"
grep -qx '1' "$workdir/dock-style"
[[ $("$theme_tool" status) == light ]]

"$theme_tool" dark
grep -qx 'prefer-dark' "$workdir/color-scheme"
grep -qx 'disabled' "$workdir/light-style"
grep -qx '2' "$workdir/panel-style"
grep -qx '2' "$workdir/dock-style"
[[ $("$theme_tool" status) == dark ]]

"$theme_tool" dark
[[ $(grep -c '^set org.gnome.desktop.interface color-scheme ' "$workdir/gsettings.log") -eq 2 ]]
[[ $(grep -c '^set org.gnome.shell.extensions.blur-my-shell.panel style-panel ' "$workdir/gsettings.log") -eq 2 ]]
[[ $(grep -c '^set org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock ' "$workdir/gsettings.log") -eq 2 ]]
[[ $(wc -l < "$workdir/extensions.log") -eq 2 ]]

printf '%s\n' prefer-dark > "$workdir/color-scheme"
printf '%s\n' disabled > "$workdir/light-style"
printf '%s\n' 2 > "$workdir/panel-style"
printf '%s\n' 2 > "$workdir/dock-style"
if MOCK_FAIL_EXTENSION=enable "$theme_tool" light >/dev/null 2>&1; then
  echo "extension enable failure unexpectedly succeeded" >&2
  exit 1
fi

if "$theme_tool" invalid >/dev/null 2>&1; then
  echo "invalid mode unexpectedly succeeded" >&2
  exit 1
fi

echo "GNOME theme mode tests passed"
