# Design

## Goal

Integrate the installed mpv with Omarchy: theme it from the **applied** theme
(without baking a palette), drive a running instance over IPC, and add media-key
bindings — all without touching the user's own mpv configuration beyond a guarded
`include=`/`input-ipc-server=` line.

## Why not a static theme?

A plugin that "supports themes" with a hardcoded palette drifts: a theme's
`colors.toml` is the source of truth. This plugin therefore carries **no hex
literal at all** — a regression test asserts that — and derives every colour from
the live file at runtime.

## Reading the applied theme

The applied theme is a **copy**:

```
~/.local/state/omarchy/current/theme/colors.toml
```

so the directory is always literally `theme` and the theme's *name* is not in the
path. To recover the name (for `status`), the plugin matches the colour set
against each directory under `/usr/share/omarchy/themes` and
`~/.config/omarchy/themes`. If nothing matches it says `(unknown)` rather than
defaulting to a fixed theme.

## Output path

```
~/.config/mpv/omarchy-theme.conf
```

A **dedicated** file. The user's `~/.config/mpv/mpv.conf` is only ever appended
to, once, with `include=~/.config/mpv/omarchy-theme.conf`. The installer guards
the append with a `grep`, so re-running it is idempotent.

**mpv config quoting pitfall.** mpv config files treat a bare `#` as the start of
a comment, so `sub-color=#ddf7ff` silently becomes `sub-color=` (an empty value)
and mpv reports *"option requires parameter"*. The generated fragment therefore
quotes every colour value: `sub-color="#ddf7ff"`. This was discovered by loading
the fragment into a real headless mpv (see `docs/VERIFICATION.md`).

## Colour mapping

| mpv option                | source colour      |
|---------------------------|--------------------|
| `sub-color`               | `foreground`       |
| `sub-outline-color`       | `background`       |
| `sub-back-color`          | `dark_background` → `background` |
| `osd-color`               | `foreground`       |
| `osd-outline-color`       | `background`       |
| `osd-back-color`          | `background`       |
| `osd-selected-color`      | `accent`           |
| `osd-selected-outline-color` | `background`    |
| `background-color`        | `background`       |

`mpv_colour()` normalises values: `#rrggbb` passes through; a Hyprland gradient
stop `rgba(rrggbbaa)` is reduced to `#rrggbb`; anything else raises, because
silently emitting an invalid colour leaves mpv on a fallback.

## IPC control

`send` speaks mpv's JSON IPC protocol directly over a unix socket (no
`python-mpv`, no `socat`). Friendly names map to raw commands:

| name          | mpv command                       |
|---------------|-----------------------------------|
| `play`        | `set_property pause false`        |
| `pause`       | `set_property pause true`         |
| `toggle`      | `cycle pause`                     |
| `next`/`prev` | `playlist-next` / `playlist-prev` |
| `stop`        | `stop`                            |
| `mute`        | `cycle mute`                      |
| `volume N`    | `set_property volume N`           |
| `volume`      | `get_property volume`             |
| `volume-up/down` | `add volume ±5`                |

The socket path is configurable (`config/mpv.json`, or `--socket`). It defaults
to `<runtime-dir>/omarchy-mpv.sock`; the installer writes a matching
`input-ipc-server=` line into `mpv.conf` (guarded, so a socket the user already
configured is left alone).

## Hook

`hooks/mpv-theme-set` is a `theme-set` hook. Two hazards drive its shape:

1. **Basename collision.** `omarchy hook install theme-set <file>` installs the
   hook under the file's **basename**, so a file literally named `theme-set`
   clobbers every other plugin's theme-set hook. Ours is `mpv-theme-set`.
2. **A copied hook cannot find its plugin.** Once installed, the hook lives in
   the hooks directory, so `$(dirname "$BASH_SOURCE")/..` is the hooks dir, not
   the plugin. The hook self-locates over `$OMARCHY_MPV_DIR`, the Omarchy plugins
   directory and the dev checkout.

The hook regenerates the fragment and, if an mpv is listening, applies the
colours live over IPC (`theme --live`) — it never starts an mpv.

## Keybinding

`bin/bindings.lua` binds mpv's transport behind **Super** + the XF86Audio media
keys (Omarchy's defaults already own the bare keys), plus `Super+Shift+Alt+M` to
open mpv. It is copied to `~/.config/hypr/mpv-bindings.lua` and required from
`hyprland.lua`.
