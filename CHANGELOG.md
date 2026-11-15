# Changelog

All notable changes to omarchy-mpv are documented here. The newest heading must
equal `version` in `manifest.json` (enforced by the policy check).

## [0.1.1] - 2026-11-15

### Fixed

- **Keybinding collision.** The `open mpv` chord was `Super + Shift + Alt + M`,
  which Omarchy already binds to its built-in **Music TUI**
  (`default/hypr/bindings/applications.lua`); the module unbound it and stole
  it. It is now `Super + Shift + Alt + V`, which collides with no Omarchy
  default, and the regression suite pins that against the installed defaults.
- **`config/mpv.json`'s `keybinding` is no longer display-only.** `bin/bindings.lua`
  is now a template rendered by `omarchy-mpv bindings` (and `install.sh`) with
  the configured chord, so editing the config changes the installed binding.
- **`install.sh` honours `config/mpv.json`.** It reads the resolved
  `theme_conf_path` / `socket_path` from the CLI (`omarchy-mpv paths`) and uses
  them for the `include=` and `input-ipc-server=` lines, so a custom path is no
  longer silently ignored (which yielded a fragment mpv never included).
- **`theme --stdout --live` now applies `--live`.** Combining the two flags
  returned before the live-IPC block; it now pushes the colours to a running
  mpv (the confirmation goes to stderr so stdout stays a clean fragment).

## [0.1.0] - 2026-10-12

### Added

- `omarchy-mpv theme` — generates an mpv configuration fragment from the applied
  Omarchy theme, read live from
  `~/.local/state/omarchy/current/theme/colors.toml` (no baked-in palette).
  Maps `foreground`/`background`/`accent`/`dark_background` onto mpv's subtitle
  (`sub-*`), on-screen-display (`osd-*`, including the selection highlight) and
  window (`background-color`) options; supports `--stdout` and `--live`.
- `omarchy-mpv send <command>` — drives a **running** mpv over its JSON IPC
  socket: `play`, `pause`, `toggle`, `next`, `prev`, `stop`, `mute`, `volume`
  (get/set), `volume-up`, `volume-down`. A clear error is printed when no mpv is
  listening rather than crashing.
- `omarchy-mpv bindings` — installs the Hyprland media-key module and wires it
  into `hyprland.lua`.
- `omarchy-mpv status` — reports the applied theme, the generated fragment, the
  IPC socket and the mpv version.
- `hooks/mpv-theme-set` — uniquely named `theme-set` hook that regenerates the
  fragment and applies the colours to a running mpv live over IPC.
  Self-locating (an installed hook cannot find its plugin via
  `$(dirname "$BASH_SOURCE")/..`).
- `config/mpv.json` — the generated fragment path, the IPC socket path and the
  keybinding, read by the CLI.
- Full test harness: unit, regression, integration, e2e and shell tests plus
  measured mutation testing, policy-as-code and CI.
