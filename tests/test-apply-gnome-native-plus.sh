#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
applicator="$repo_root/scripts/apply-gnome-native-plus.sh"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

mkdir -p "$workdir/bin" "$workdir/Papirus" "$workdir/bms-schemas" "$workdir/htb-schemas"
: > "$workdir/gsettings.log"
: > "$workdir/dconf.log"

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
state_name=${schema//./_}__${key}
state_file="$MOCK_STATE_DIR/$state_name"

allowed_target() {
  case "$schema $key" in
    "org.gnome.desktop.interface icon-theme" | \
    "org.gnome.shell.extensions.dash-to-dock custom-background-color" | \
    "org.gnome.shell.extensions.dash-to-dock apply-glossy-effect" | \
    "org.gnome.shell.extensions.dash-to-dock apply-custom-theme" | \
    "org.gnome.shell.extensions.dash-to-dock transparency-mode" | \
    "org.gnome.shell.extensions.blur-my-shell.dash-to-dock blur" | \
    "org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur" | \
    "org.gnome.shell.extensions.blur-my-shell.dash-to-dock override-background" | \
    "org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock" | \
    "org.gnome.shell.extensions.blur-my-shell.panel style-panel" | \
    "org.gnome.shell.extensions.blur-my-shell.hidetopbar compatibility")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

case "$command" in
  get)
    if [[ $schema == org.gnome.shell && $key == enabled-extensions ]]; then
      printf "%s\n" "['dash-to-dock@micxgx.gmail.com', 'desktop-cube@schneegans.github.com']"
    elif allowed_target; then
      if [[ -f $state_file ]]; then
        cat "$state_file"
      else
        case "$key" in
          icon-theme) printf "%s\n" "'Qogir'" ;;
          transparency-mode) printf "%s\n" "'FIXED'" ;;
          style-dash-to-dock | style-panel) printf '%s\n' 0 ;;
          custom-background-color | apply-glossy-effect | apply-custom-theme)
            printf '%s\n' true
            ;;
          *) printf '%s\n' false ;;
        esac
      fi
    else
      echo "unexpected gsettings get: $schema $key" >&2
      exit 81
    fi
    ;;
  set)
    allowed_target || {
      echo "unexpected gsettings set: $schema $key" >&2
      exit 82
    }
    value=${value//\'/}
    printf '%s %s %s\n' "$schema" "$key" "$value" >> "$MOCK_STATE_DIR/gsettings.log"
    printf '%s\n' "$value" > "$state_file"
    ;;
  *)
    echo "unexpected gsettings command: $command" >&2
    exit 83
    ;;
esac
MOCK

cat > "$workdir/bin/dconf" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

[[ ${1:-} == dump && ${2:-} == /*/ ]] || {
  echo "unexpected dconf command: $*" >&2
  exit 84
}
printf 'dump %s\n' "$2" >> "$MOCK_STATE_DIR/dconf.log"
printf '[mock]\nvalue=true\n'
MOCK

cat > "$workdir/bin/gnome-extensions" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == list && ${2:-} == --enabled ]] || {
  echo "unexpected extension command: $*" >&2
  exit 85
}
printf '%s\n' dash-to-dock@micxgx.gmail.com desktop-cube@schneegans.github.com
MOCK

chmod +x "$workdir/bin/gsettings" "$workdir/bin/dconf" "$workdir/bin/gnome-extensions"
export MOCK_STATE_DIR="$workdir"
export PATH="$workdir/bin:$PATH"
export PAPIRUS_DIR="$workdir/Papirus"
export BMS_SCHEMA_DIR="$workdir/bms-schemas"
export HTB_SCHEMA_DIR="$workdir/htb-schemas"

backup_dir="$workdir/backup"
"$applicator" --apply --backup-dir "$backup_dir"

test -s "$backup_dir/interface.dconf"
test -s "$backup_dir/dash-to-dock.dconf"
test -s "$backup_dir/blur-my-shell.dconf"
test -s "$backup_dir/hidetopbar.dconf"
test -s "$backup_dir/enabled-extensions.gvariant"
test -s "$backup_dir/enabled-extensions.txt"
test -x "$backup_dir/rollback.sh"

grep -Fqx "org.gnome.desktop.interface icon-theme Papirus" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.dash-to-dock custom-background-color false" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.dash-to-dock apply-glossy-effect false" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.dash-to-dock apply-custom-theme false" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.dash-to-dock transparency-mode DEFAULT" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock blur true" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur true" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock override-background true" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock 2" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.panel style-panel 2" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.hidetopbar compatibility true" "$workdir/gsettings.log"

grep -Fq "dconf reset -f /org/gnome/desktop/interface/" "$backup_dir/rollback.sh"
grep -Fq "dconf reset -f /org/gnome/shell/extensions/dash-to-dock/" "$backup_dir/rollback.sh"
grep -Fq "dconf reset -f /org/gnome/shell/extensions/blur-my-shell/" "$backup_dir/rollback.sh"
grep -Fq "dconf reset -f /org/gnome/shell/extensions/hidetopbar/" "$backup_dir/rollback.sh"
grep -Fq "enabled-extensions.gvariant" "$backup_dir/rollback.sh"

if "$applicator" --apply --backup-dir "$backup_dir" >/dev/null 2>&1; then
  echo "existing backup directory unexpectedly accepted" >&2
  exit 1
fi

if "$applicator" --backup-dir "$workdir/other" >/dev/null 2>&1; then
  echo "missing --apply unexpectedly accepted" >&2
  exit 1
fi

echo "GNOME native-plus applicator tests passed"
