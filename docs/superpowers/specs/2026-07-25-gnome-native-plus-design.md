# GNOME Native-Plus Desktop Design

Date: 2026-07-25

## Goal

Refine the MacBookPro11,3 GNOME desktop into a polished, Mac-familiar
environment while retaining GNOME's native interaction model and prioritizing
smoothness on the Intel Iris Pro graphics path.

The finished desktop should feel intentional and visually distinctive without
depending on a fragile third-party shell theme, continuously expensive effects,
or macOS-style keyboard remapping.

## Current State

- GNOME Shell 50.3 on the production Intel/i915 graphics path.
- Adwaita application theme with dark mode currently preferred.
- Qogir icon theme, with Papirus already installed.
- Window controls on the left.
- Dynamic workspaces with four currently available.
- Enabled shell extensions:
  - Dash-to-Dock
  - AppIndicator
  - Blur My Shell
  - Maximize Window Into New Workspace
  - Hide Top Bar
  - Deperto
  - Desktop Cube
- Dash-to-Dock is on the left and uses the user's established intelligent-hide
  behavior. Its current appearance includes a fixed white background at 27%
  opacity and a glossy effect.
- Hide Top Bar already has intellihide enabled and shows the panel in Overview.
- Blur My Shell currently uses static panel blur but does not blur Dash-to-Dock.

## Approved Experience

### Native foundation

- Keep Adwaita application and window styling.
- Keep left-side window controls.
- Do not install or activate a third-party GTK or GNOME Shell theme.
- Do not change keyboard mappings or shortcuts. The user explicitly chose to
  learn GNOME's native keyboard model.

### Dock

- Preserve the existing left-side placement and all established behavioral
  settings, including intelligent hiding.
- Replace the fixed white/glossy treatment with theme-aware luminous glass:
  brighter frosted translucency in light mode and deeper translucent material
  in dark mode.
- Treat application and Shell theme as one user-facing mode. GNOME's
  `org.gnome.desktop.interface color-scheme` changes application preference but
  does not switch GNOME Shell. Use a single explicit theme command to set that
  preference and enable/disable the installed official Light Style extension
  together. The same command must select Blur My Shell's explicit light or dark
  material presets for both panel and Dash-to-Dock; those components do not
  listen to the application color preference themselves.
- Use moderate rounded static blur rather than continuously recomputed dynamic
  blur.
- Keep icon sizing and layout usable on the built-in display; do not enlarge
  the dock merely for closer macOS imitation.
- Use restrained, legible running indicators rather than attention-grabbing
  animation.

### Top bar

- Keep the bar visible on the desktop and with ordinary windows.
- Hide it when a maximized window occupies its space and in full-screen use.
- Retain visibility in Overview.
- Use a restrained theme-aware material that supports, rather than competes
  with, the dock.

### Icons and motion

- Trial Papirus as the icon theme.
- Preserve Qogir as the explicit rollback selection.
- Keep Desktop Cube enabled as an intentional signature effect.
- Do not add continuous decorative animation or new effects extensions.
- Existing native GNOME workspace gestures and dynamic workspaces remain
  unchanged.

## Performance Policy

Smoothness has priority over spectacle.

- Prefer static blur for dock and panel.
- Avoid whole-window blur and additional background effects.
- Do not add a daemon, polling process, custom GNOME Shell stylesheet, or
  another extension for light/dark adaptation.
- A small non-resident theme command is permitted. It must accept an explicit
  `light` or `dark` target, make the application and Shell modes agree, verify
  the resulting state including the corresponding Blur My Shell material
  presets, and exit.
- Use the installed extensions' native theme integration where possible.
- If the chosen luminous treatment causes visible stutter, extension errors, or
  a repeatable sustained GNOME Shell CPU/GPU increase, reduce or remove blur
  before compromising interaction latency.

## Implementation Boundaries

The implementation may change only:

- a repository-owned, test-covered theme command and its user-local installed
  copy;
- `org.gnome.desktop.interface` icon/theme-adjacent keys needed for the Papirus
  trial and unified light/dark selection;
- enablement of the already installed official Light Style extension;
- `org.gnome.shell.extensions.dash-to-dock` appearance keys;
- the installed Blur My Shell panel and Dash-to-Dock component keys;
- the installed Hide Top Bar keys needed to enforce the approved visibility
  behavior.

It must not:

- change Dash-to-Dock placement, favorites, click actions, hotkeys, visibility
  policy, mount/trash behavior, monitor selection, or workspace isolation;
- change keyboard or touchpad mappings;
- disable or retune Desktop Cube;
- change application GTK themes;
- install another package or extension;
- alter kernel, GPU, power, audio, Bluetooth, suspend, PSD, boot, update, or
  recovery policy;
- touch Starlight, Chrome, Flatpak data, or caches.

## Staged Application

1. Export the relevant dconf settings and record enabled extensions.
2. Record a short idle GNOME Shell CPU baseline with the desktop undisturbed.
3. Switch only the icon theme to Papirus and verify common applications,
   symbolic status icons, and Flatpak launchers.
4. Change only dock appearance settings. Verify placement and behavior are
   unchanged, then inspect both light and dark modes.
5. Change only panel material and intellihide settings. Verify normal,
   maximized, full-screen, and Overview states.
6. Install and test the unified theme command. Exercise both explicit targets
   and restore the user's original dark preference after the light/dark test.
7. Recheck GNOME Shell CPU/GPU behavior, Shell/extension journal errors, enabled
   extensions, and all protected system invariants.

Each stage is independently reversible. A later stage must not be layered over
an unresolved failure from an earlier stage.

## Verification

The result is acceptable only if:

- Papirus renders correctly in the dock, top bar, Overview, Nautilus, Settings,
  Chrome, Starlight, and representative Flatpak launchers, meaning no missing
  or broken icons. Shell symbolic/status icons and application-supplied icons
  need not originate from Papirus.
- switching GNOME between light and dark produces legible dock and panel
  materials without a fixed inappropriate tint, when performed through the
  unified theme command;
- the unified theme command is idempotent, changes no unrelated extension
  enablement, reports failure if either application or Shell state does not
  match the requested target, and has no resident process;
- the dock remains left-mounted and retains its previous hide/show behavior;
- the panel is visible with non-maximized windows, hidden for maximized and
  full-screen windows, and visible in Overview;
- Desktop Cube and every previously enabled extension remain enabled and free
  of new Shell errors;
- GNOME Shell remains subjectively smooth and shows no repeatable material
  resource regression;
- no unrelated system policy or protected data changes.

## Rollback

- Keep a timestamped focused dconf export created immediately before mutation.
- Keep a copy of the pre-existing enabled-extension list. Removing the unified
  theme command and restoring the dconf export must remove its local behavior.
- Rollback must first reset each exact scoped dconf subtree and then load its
  dump; loading a dump alone does not remove values that were defaults before
  mutation. The enabled-extension key must be backed up and restored
  separately.
- Restore that export to return Dash-to-Dock, Blur My Shell, Hide Top Bar,
  interface and extension settings to their exact prior values.
- If only the icon trial is rejected, set
  `org.gnome.desktop.interface icon-theme` back to `Qogir`.
- A rollback must restore the user's original light/dark preference and confirm
  the enabled-extension list.

## Deferred Possibilities

- A custom GNOME Shell stylesheet or theme-switching helper.
- Additional animation/effects extensions.
- Disabling Desktop Cube.
- Keyboard remapping toward macOS.
- Any GTK or libadwaita theming override.

These require a separate design and are not implicit follow-up work.
