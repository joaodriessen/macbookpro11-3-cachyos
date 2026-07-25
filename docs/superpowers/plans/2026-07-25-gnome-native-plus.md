# GNOME Native-Plus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a reversible, smoothness-first GNOME polish pass with Papirus icons, theme-aware luminous dock/panel materials, preserved dock/cube behavior, and a unified non-resident light/dark command.

**Architecture:** Two repository-owned Bash tools separate concerns. `gnome-theme-mode.sh` synchronizes GNOME application color preference with the installed official Light Style extension; `apply-gnome-native-plus.sh` snapshots the relevant dconf state and applies only the approved appearance keys. Mock-command shell tests prove command scope and failure behavior before either tool touches the live desktop.

**Tech Stack:** Bash 5, GSettings/dconf, `gnome-extensions`, GNOME Shell 50.3, Dash-to-Dock 105, Blur My Shell, Hide Top Bar, Papirus.

## Global Constraints

- Keep native Adwaita application and window styling.
- Do not change any keyboard or touchpad mapping.
- Preserve Dash-to-Dock's left position and all existing behavioral settings.
- Keep Desktop Cube enabled and unchanged.
- Add no package, daemon, polling process, custom Shell CSS, GTK theme, or new extension.
- Use only the already installed Papirus and official Light Style extension.
- Prefer static blur; smoothness has priority over spectacle.
- Preserve Starlight, Chrome, Flatpak data/caches, and all kernel/GPU/power/audio/Bluetooth/suspend/PSD/boot/update/recovery policy.
- Every mutation must have a focused pre-change backup and exact rollback.

---

### Task 1: Unified Light/Dark Command

**Files:**
- Create: `scripts/gnome-theme-mode.sh`
- Create: `tests/test-gnome-theme-mode.sh`

**Interfaces:**
- Consumes: `gsettings`, `gnome-extensions`, installed UUID `light-style@gnome-shell-extensions.gcampax.github.com`
- Produces: `gnome-theme-mode.sh light|dark|status`; exit 0 only when application, Shell, panel and dock states match

- [ ] **Step 1: Write the failing command-contract test**

Create a temporary mock `PATH` containing stateful `gsettings` and
`gnome-extensions` commands. Assert:

```bash
"$theme_tool" light
grep -qx "prefer-light" "$workdir/color-scheme"
grep -qx "enabled" "$workdir/light-style"
grep -qx "0" "$workdir/panel-style"
grep -qx "0" "$workdir/dock-style"

"$theme_tool" dark
grep -qx "prefer-dark" "$workdir/color-scheme"
grep -qx "disabled" "$workdir/light-style"
grep -qx "0" "$workdir/panel-style"
grep -qx "0" "$workdir/dock-style"

"$theme_tool" dark
[[ $(grep -c '^set ' "$workdir/gsettings.log") -eq 2 ]]

"$theme_tool" status | grep -qx 'dark'

if "$theme_tool" invalid 2>/dev/null; then
  exit 1
fi
```

The mocks must reject every schema/key or extension UUID outside the approved
interface and must support an injected failed enable/disable operation.

- [ ] **Step 2: Run the test and verify the red state**

Run:

```bash
bash tests/test-gnome-theme-mode.sh
```

Expected: failure because `scripts/gnome-theme-mode.sh` does not exist.

- [ ] **Step 3: Implement the minimal command**

Implement strict Bash with:

```text
Usage: gnome-theme-mode.sh light|dark|status
```

For `light`, set `org.gnome.desktop.interface color-scheme` to
`prefer-light`, enable the official Light Style UUID, select Blur My Shell
`panel style-panel=0` and `dash-to-dock style-dash-to-dock=0`, then verify all
four values. For `dark`, set `prefer-dark`, disable the UUID and retain both
transparent Blur My Shell style values `0`, then verify all four values.
`status` prints only `light`, `dark`, or `mixed` and performs no mutation.
Reject any other argument. Do not call `sudo`, install packages, touch extension
files, or modify the rest of the enabled-extension list.

- [ ] **Step 4: Run the focused tests**

Run:

```bash
bash tests/test-gnome-theme-mode.sh
bash -n scripts/gnome-theme-mode.sh tests/test-gnome-theme-mode.sh
shellcheck scripts/gnome-theme-mode.sh tests/test-gnome-theme-mode.sh
```

Expected: all exit 0, including the injected failure case.

- [ ] **Step 5: Commit Task 1**

```bash
git add scripts/gnome-theme-mode.sh tests/test-gnome-theme-mode.sh
git commit -m "feat: add unified GNOME theme mode command"
```

### Task 2: Scoped GNOME Appearance Applicator

**Files:**
- Create: `scripts/apply-gnome-native-plus.sh`
- Create: `tests/test-apply-gnome-native-plus.sh`

**Interfaces:**
- Consumes: `gsettings`, `dconf`, `gnome-extensions`, `--apply`, optional `--backup-dir DIR`
- Produces: focused backup directory and the exact approved Papirus/dock/blur settings

- [ ] **Step 1: Write the failing scope and backup test**

Use mock commands and assert that `--apply --backup-dir "$workdir/backup"`:

```bash
test -s "$workdir/backup/interface.dconf"
test -s "$workdir/backup/dash-to-dock.dconf"
test -s "$workdir/backup/blur-my-shell.dconf"
test -s "$workdir/backup/hidetopbar.dconf"
test -s "$workdir/backup/enabled-extensions.txt"
grep -Fqx "org.gnome.desktop.interface icon-theme Papirus" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.dash-to-dock custom-background-color false" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.dash-to-dock apply-glossy-effect false" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.dash-to-dock apply-custom-theme false" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock blur true" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur true" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock override-background true" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock 0" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.panel style-panel 0" "$workdir/gsettings.log"
grep -Fqx "org.gnome.shell.extensions.blur-my-shell.hidetopbar compatibility true" "$workdir/gsettings.log"
```

The mock must fail the test if the tool writes any dock behavior key, keyboard
schema, Desktop Cube schema, GTK theme key, or unapproved extension state.
Assert a missing/previously populated backup directory is rejected rather than
overwritten.

- [ ] **Step 2: Run the test and verify the red state**

Run:

```bash
bash tests/test-apply-gnome-native-plus.sh
```

Expected: failure because `scripts/apply-gnome-native-plus.sh` does not exist.

- [ ] **Step 3: Implement the minimal applicator**

Implement strict Bash that:

1. Requires `--apply`.
2. Creates a new mode-0700 backup directory, defaulting below
   `${XDG_STATE_HOME:-$HOME/.local/state}/catchybook/gnome-native-plus/`.
3. Exports focused dconf subtrees for interface, Dash-to-Dock, Blur My Shell and
   Hide Top Bar, separately exports `org.gnome.shell enabled-extensions`, and
   records `gnome-extensions list --enabled`.
4. Verifies `Papirus` and all required schemas/keys exist before mutation.
5. Sets only the exact values asserted in Step 1.
6. Reads every target back and exits nonzero on a mismatch.
7. Prints the backup path and exact rollback commands that reset each scoped
   subtree before `dconf load`, then restore enabled extensions separately.

Use Blur My Shell's local schema directory
`$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas` and
Hide Top Bar's equivalent schema directory for their settings.

- [ ] **Step 4: Run focused and repository tests**

Run:

```bash
bash tests/test-apply-gnome-native-plus.sh
bash tests/test-gnome-theme-mode.sh
bash -n scripts/apply-gnome-native-plus.sh tests/test-apply-gnome-native-plus.sh
shellcheck scripts/apply-gnome-native-plus.sh tests/test-apply-gnome-native-plus.sh
```

Expected: all exit 0.

- [ ] **Step 5: Commit Task 2**

```bash
git add scripts/apply-gnome-native-plus.sh tests/test-apply-gnome-native-plus.sh
git commit -m "feat: add reversible GNOME native-plus applicator"
```

### Task 3: Live Baseline, Staged Application, and Verification

**Files:**
- Install from: `scripts/gnome-theme-mode.sh`
- Install to: `/home/joao/.local/bin/catchybook-theme`
- Create at runtime: `/home/joao/.local/state/catchybook/gnome-native-plus/<timestamp>/`
- Update: `/home/joao/CATCHYBOOK_PROJECT_ANCHOR.md`

**Interfaces:**
- Consumes: tested Task 1 and Task 2 commands
- Produces: verified live GNOME configuration plus durable rollback evidence

- [ ] **Step 1: Capture the pre-change gate**

Record:

```bash
gsettings get org.gnome.desktop.interface color-scheme
gsettings get org.gnome.desktop.interface icon-theme
gsettings list-recursively org.gnome.shell.extensions.dash-to-dock
gnome-extensions list --enabled
systemctl --failed --no-legend
systemctl --user --failed --no-legend
journalctl --user -b _COMM=gnome-shell --since '-10 min' --no-pager
```

Sample `gnome-shell` CPU activity for 15 seconds while the desktop is not being
actively manipulated. Preserve the raw output in the new backup directory;
this is a regression reference, not a synthetic benchmark.

- [ ] **Step 2: Run the tested applicator**

Run:

```bash
scripts/apply-gnome-native-plus.sh --apply --backup-dir "$backup_dir"
```

Immediately verify Papirus, every approved dock/blur key, dock position
`LEFT`, current intellihide/autohide values, enabled Desktop Cube, and zero
failed units. Roll back immediately if any protected value differs.

- [ ] **Step 3: Install and exercise the unified theme command**

Install with mode 0755:

```bash
install -Dm755 scripts/gnome-theme-mode.sh /home/joao/.local/bin/catchybook-theme
```

Run `catchybook-theme light`, verify `prefer-light` plus enabled official Light
Style plus transparent panel/dock material presets, inspect dock/panel/icon
legibility, then run `catchybook-theme dark` and verify `prefer-dark` plus
disabled official Light Style while retaining transparent panel/dock material
presets. Leave the system in dark mode, matching the pre-change preference.

- [ ] **Step 4: Verify behavior and smoothness**

Manually and programmatically check:

- dock remains left and retains its original hide/show behavior;
- non-maximized window leaves the panel visible;
- maximized and full-screen windows hide the panel; also record the installed
  Hide Top Bar behavior for an active tiled/non-maximized window that touches
  the panel, because its intellihide algorithm is overlap-based rather than
  strictly maximization-based;
- Overview shows the panel;
- Desktop Cube remains enabled and works;
- Papirus produces no missing/broken icons in representative native, browser,
  Starlight and Flatpak launchers; Shell symbolic icons and app-supplied icons
  are not required to come from Papirus;
- no new GNOME Shell/extension errors appear;
- a second 15-second idle sample shows no repeatable sustained Shell CPU/GPU
  regression or visible stutter.

If behavior cannot be programmatically asserted without intrusive UI
automation, record it as a bounded user-visible validation rather than
fabricating a pass.

- [ ] **Step 5: Run the full safety gate**

Run all repository tests, `bash -n` over repository shell files, ShellCheck over
the four new files, `scripts/verify-all.sh`, system/user failed-unit checks, and
the established production invariants: Intel primary, EEVDF, PPD balanced,
Bluetooth USB `on`, HDA power save `0`, PSD limit `2`, and protected data paths
present.

- [ ] **Step 6: Update the project anchor and commit documentation**

Record exact changed values, backup directory, installed helper checksum,
light/dark results, performance evidence, unresolved visual-only checks, and
rollback commands in `/home/joao/CATCHYBOOK_PROJECT_ANCHOR.md`.

Commit any repository documentation changes separately without staging the
pre-existing modified `README.md` or `scripts/hybrid-gpu-test/README.md`.
