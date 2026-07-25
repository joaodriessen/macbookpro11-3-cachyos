#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") light|dark|status" >&2
}

mode=${1:-}
[[ $# -eq 1 && $mode =~ ^(light|dark|status)$ ]] || {
  usage
  exit 2
}

light_style_uuid=light-style@gnome-shell-extensions.gcampax.github.com
bms_schema_dir=${BMS_SCHEMA_DIR:-"$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas"}
interface_schema=org.gnome.desktop.interface
panel_schema=org.gnome.shell.extensions.blur-my-shell.panel
dock_schema=org.gnome.shell.extensions.blur-my-shell.dash-to-dock

read_setting() {
  local schema=$1
  local key=$2

  if [[ $schema == "$interface_schema" ]]; then
    gsettings get "$schema" "$key" | tr -d "'"
  else
    gsettings --schemadir "$bms_schema_dir" get "$schema" "$key"
  fi
}

write_setting() {
  local schema=$1
  local key=$2
  local value=$3

  [[ $(read_setting "$schema" "$key") == "$value" ]] && return
  if [[ $schema == "$interface_schema" ]]; then
    gsettings set "$schema" "$key" "$value"
  else
    gsettings --schemadir "$bms_schema_dir" set "$schema" "$key" "$value"
  fi
}

extension_state() {
  if gnome-extensions info "$light_style_uuid" | grep -q 'Enabled: Yes'; then
    echo enabled
  else
    echo disabled
  fi
}

current_mode() {
  local scheme panel_style dock_style light_style
  scheme=$(read_setting "$interface_schema" color-scheme)
  panel_style=$(read_setting "$panel_schema" style-panel)
  dock_style=$(read_setting "$dock_schema" style-dash-to-dock)
  light_style=$(extension_state)

  if [[ $scheme == prefer-light && $panel_style == 1 && $dock_style == 1 && $light_style == enabled ]]; then
    echo light
  elif [[ $scheme == prefer-dark && $panel_style == 2 && $dock_style == 2 && $light_style == disabled ]]; then
    echo dark
  else
    echo mixed
  fi
}

if [[ $mode == status ]]; then
  current_mode
  exit
fi

if [[ $mode == light ]]; then
  target_scheme=prefer-light
  target_style=1
  target_extension=enabled
else
  target_scheme=prefer-dark
  target_style=2
  target_extension=disabled
fi

write_setting "$interface_schema" color-scheme "$target_scheme"
write_setting "$panel_schema" style-panel "$target_style"
write_setting "$dock_schema" style-dash-to-dock "$target_style"

if [[ $(extension_state) != "$target_extension" ]]; then
  if [[ $target_extension == enabled ]]; then
    gnome-extensions enable "$light_style_uuid"
  else
    gnome-extensions disable "$light_style_uuid"
  fi
fi

actual=$(current_mode)
[[ $actual == "$mode" ]] || {
  echo "Failed to establish GNOME theme mode '$mode' (actual: $actual)" >&2
  exit 1
}

echo "$actual"
