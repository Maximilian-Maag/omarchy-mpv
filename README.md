# omarchy-mpv

Integrate the installed **mpv** media player with [Omarchy](https://omarchy.org):

- **Theme it from the applied Omarchy theme** — no palette is baked into the
  plugin; every colour is read live from
  `~/.local/state/omarchy/current/theme/colors.toml`, so any theme (including one
  you wrote) themes mpv correctly.
- **Drive a running mpv** — play / pause / next / prev / stop / mute / volume
  over mpv's JSON IPC socket.
- **Media-key bindings** — Super + the XF86Audio media keys control mpv.

Plugin id: `Maximilian-Maag.mpv`.

## Install

```bash
git clone <this-repo> ~/Work/omarchy-mpv
cd ~/Work/omarchy-mpv
./install.sh
```

`install.sh` symlinks `omarchy-mpv` onto `PATH` (`/usr/local/bin`), generates the
theme fragment, adds a guarded `include=` and `input-ipc-server=` line to your
`~/.config/mpv/mpv.conf` (nothing you wrote is overwritten), installs the
`theme-set` hook and wires the Hyprland keybindings.

## Usage

```bash
omarchy-mpv status            # applied theme, fragment, socket, mpv version
omarchy-mpv theme             # (re)generate the mpv theme fragment
omarchy-mpv theme --stdout    # print it instead of writing it
omarchy-mpv theme --live      # also apply it to a running mpv over IPC
omarchy-mpv send toggle       # play/pause a running mpv
omarchy-mpv send next
omarchy-mpv send volume 70    # set volume
omarchy-mpv send volume       # print the current volume
omarchy-mpv bindings          # install the Hyprland media-key module
```

## How the theming works

The applied theme is a **copy** at
`~/.local/state/omarchy/current/theme/colors.toml` — the theme's *name* is not in
the path. `theme` parses it and writes a **dedicated** fragment to
`~/.config/mpv/omarchy-theme.conf`. Your own `~/.config/mpv/mpv.conf` is only ever
appended to, once, with:

```
include=~/.config/mpv/omarchy-theme.conf
```

Nothing else in your mpv configuration is touched. Because mpv config files treat
a bare `#` as a comment, colour values are written quoted (`sub-color="#ddf7ff"`).

Colour mapping: `foreground` → subtitle/OSD text, `background` → outlines and the
window background, `dark_background` → subtitle backing, `accent` → the OSD
selection highlight.

## Driving mpv over IPC

For `send` to reach mpv, mpv must expose its JSON IPC socket. `install.sh` adds:

```
input-ipc-server=<runtime-dir>/omarchy-mpv.sock
```

to your `mpv.conf`, so any mpv you launch normally is controllable. The socket
path is configurable in `config/mpv.json` (or per-invocation with `--socket`).
Because the path is fixed, run one mpv instance at a time, or point `--socket` at
a per-instance socket.

## Media keys

Omarchy's defaults already own the bare `XF86Audio*` keys, so this plugin binds
mpv behind **Super** to coexist:

| Binding | Action |
|---------|--------|
| `Super + XF86AudioPlay` | play / pause |
| `Super + XF86AudioNext` | next |
| `Super + XF86AudioPrev` | previous |
| `Super + XF86AudioStop` | stop |
| `Super + Shift + Alt + M` | open mpv |

## Development

```bash
make check      # policy + unit + regression (fast)
make test       # the whole suite: policy, unit, regression, integration, e2e, shell, mutation
make mutation   # just the mutation pass
```

Tests never require mpv to be installed: the unit and integration suites drive a
**fake** IPC socket server. The e2e suite uses a real headless mpv when one is
present and skips cleanly otherwise.

## License

MIT — see [LICENSE](LICENSE).
