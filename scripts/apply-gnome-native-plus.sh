#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") --apply [--backup-dir DIR]" >&2
}

apply=false
backup_dir=
while (($#)); do
  case "$1" in
    --apply)
      apply=true
      shift
      ;;
    --backup-dir)
      [[ $# -ge 2 ]] || {
        usage
        exit 2
      }
      backup_dir=$2
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ $apply == true ]] || {
  usage
  exit 2
}

if [[ -z $backup_dir ]]; then
  state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
  backup_dir="$state_root/catchybook/gnome-native-plus/$(date +%Y%m%d-%H%M%S)"
fi

[[ ! -e $backup_dir ]] || {
  echo "Refusing existing backup path: $backup_dir" >&2
  exit 1
}

papirus_dir=${PAPIRUS_DIR:-/usr/share/icons/Papirus}
bms_schema_dir=${BMS_SCHEMA_DIR:-"$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas"}
htb_schema_dir=${HTB_SCHEMA_DIR:-"$HOME/.local/share/gnome-shell/extensions/hidetopbar@mathieu.bidon.ca/schemas"}

for command_name in dconf gnome-extensions gsettings; do
  command -v "$command_name" >/dev/null || {
    echo "Required command not found: $command_name" >&2
    exit 1
  }
done

for required_dir in "$papirus_dir" "$bms_schema_dir" "$htb_schema_dir"; do
  [[ -d $required_dir ]] || {
    echo "Required directory not found: $required_dir" >&2
    exit 1
  }
done

install -d -m 0700 "$backup_dir"
dconf dump /org/gnome/desktop/interface/ > "$backup_dir/interface.dconf"
dconf dump /org/gnome/shell/extensions/dash-to-dock/ > "$backup_dir/dash-to-dock.dconf"
dconf dump /org/gnome/shell/extensions/blur-my-shell/ > "$backup_dir/blur-my-shell.dconf"
dconf dump /org/gnome/shell/extensions/hidetopbar/ > "$backup_dir/hidetopbar.dconf"
gsettings get org.gnome.shell enabled-extensions > "$backup_dir/enabled-extensions.gvariant"
gnome-extensions list --enabled > "$backup_dir/enabled-extensions.txt"

escaped_backup=$(printf '%q' "$backup_dir")
backup_ref=\$backup_dir
enabled_ref=\$enabled_extensions
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  printf 'backup_dir=%s\n' "$escaped_backup"
  for subtree in \
    /org/gnome/desktop/interface/ \
    /org/gnome/shell/extensions/dash-to-dock/ \
    /org/gnome/shell/extensions/blur-my-shell/ \
    /org/gnome/shell/extensions/hidetopbar/; do
    filename=${subtree%/}
    filename=${filename##*/}
    [[ $filename != interface ]] || filename=interface
    printf 'dconf reset -f %q\n' "$subtree"
    printf 'dconf load %q < "%s/%s.dconf"\n' "$subtree" "$backup_ref" "$filename"
  done
  printf "enabled_extensions=\$(<\"%s/enabled-extensions.gvariant\")\n" "$backup_ref"
  printf 'gsettings set org.gnome.shell enabled-extensions "%s"\n' "$enabled_ref"
} > "$backup_dir/rollback.sh"
chmod 0700 "$backup_dir/rollback.sh"

normalize() {
  tr -d "'"
}

set_and_verify() {
  local schema_dir=$1
  local schema=$2
  local key=$3
  local target=$4
  local current
  local -a command=(gsettings)

  [[ -z $schema_dir ]] || command+=(--schemadir "$schema_dir")
  current=$("${command[@]}" get "$schema" "$key" | normalize)
  if [[ $current != "$target" ]]; then
    "${command[@]}" set "$schema" "$key" "$target"
  fi
  current=$("${command[@]}" get "$schema" "$key" | normalize)
  [[ $current == "$target" ]] || {
    echo "Failed to set $schema $key to $target (actual: $current)" >&2
    exit 1
  }
}

set_and_verify '' org.gnome.desktop.interface icon-theme Papirus
set_and_verify '' org.gnome.shell.extensions.dash-to-dock custom-background-color false
set_and_verify '' org.gnome.shell.extensions.dash-to-dock apply-glossy-effect false
set_and_verify '' org.gnome.shell.extensions.dash-to-dock apply-custom-theme false
set_and_verify '' org.gnome.shell.extensions.dash-to-dock transparency-mode DEFAULT
set_and_verify "$bms_schema_dir" org.gnome.shell.extensions.blur-my-shell.dash-to-dock blur true
set_and_verify "$bms_schema_dir" org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur true
set_and_verify "$bms_schema_dir" org.gnome.shell.extensions.blur-my-shell.dash-to-dock override-background true
set_and_verify "$bms_schema_dir" org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock 2
set_and_verify "$bms_schema_dir" org.gnome.shell.extensions.blur-my-shell.panel style-panel 2
set_and_verify "$bms_schema_dir" org.gnome.shell.extensions.blur-my-shell.hidetopbar compatibility true

echo "GNOME native-plus appearance applied"
echo "Backup: $backup_dir"
echo "Rollback: $backup_dir/rollback.sh"
