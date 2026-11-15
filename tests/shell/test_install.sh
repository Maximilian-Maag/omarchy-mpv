#!/bin/bash
# Shell tests for install.sh — hermetic (throwaway HOME/XDG, stubbed omarchy/sudo).
# The key guarantee: an existing user mpv.conf is never destroyed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/install.sh"
pass=0; fail=0
ok()  { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export XDG_STATE_HOME="$SANDBOX/state"
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="$SANDBOX/data"
export XDG_RUNTIME_DIR="$SANDBOX/run"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_STATE_HOME/omarchy/current/theme"
cat > "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
dark_background = "#080910"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML

# stub omarchy + sudo, first on PATH
BIN="$SANDBOX/bin"; mkdir -p "$BIN"; export PATH="$BIN:$PATH"
printf '#!/bin/bash\nexit 0\n' > "$BIN/omarchy"
printf '#!/bin/bash\nexit 0\n' > "$BIN/sudo"
chmod +x "$BIN/omarchy" "$BIN/sudo"

# a pre-existing user config with content that must survive
MPV_DIR="$XDG_CONFIG_HOME/mpv"
mkdir -p "$MPV_DIR"
printf '# my precious config\nvo=gpu\n' > "$MPV_DIR/mpv.conf"
mkdir -p "$XDG_CONFIG_HOME/hypr"
printf -- '-- main config\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"

bash "$INSTALL" >"$SANDBOX/install.log" 2>&1
rc=$?

if (( rc == 0 )); then ok "install.sh exit 0"; else bad "install.sh exit $rc"; cat "$SANDBOX/install.log"; fi

# closing hint must print the configured chord, not the stale SUPER+SHIFT+ALT+M (#5)
if grep -qF "SUPER + SHIFT + ALT + V opens it" "$SANDBOX/install.log"; then
  ok "closing hint prints the configured chord"
else
  bad "closing hint did not print the configured chord"; cat "$SANDBOX/install.log"
fi
if grep -qi "alt.*M opens it" "$SANDBOX/install.log"; then
  bad "closing hint still advertises the old chord"
else
  ok "closing hint does not advertise the old chord"
fi

if [[ -f "$MPV_DIR/mpv.conf" ]] && grep -q "my precious config" "$MPV_DIR/mpv.conf"; then
  ok "existing mpv.conf preserved"
else
  bad "user mpv.conf was destroyed"
fi
if grep -q "include=" "$MPV_DIR/mpv.conf"; then
  ok "include= line appended"
else
  bad "no include= line added"
fi
if grep -q "input-ipc-server" "$MPV_DIR/mpv.conf"; then
  ok "input-ipc-server line appended"
else
  bad "no input-ipc-server line added"
fi
if [[ -f "$MPV_DIR/omarchy-theme.conf" ]]; then
  ok "theme fragment generated"
else
  bad "theme fragment not generated"
fi
if [[ -f "$XDG_CONFIG_HOME/hypr/mpv-bindings.lua" ]]; then
  ok "hyprland bindings module installed"
else
  bad "bindings module missing"
fi
if grep -q "hypr.mpv-bindings" "$XDG_CONFIG_HOME/hypr/hyprland.lua"; then
  ok "keybindings wired into hyprland.lua"
else
  bad "keybindings not wired"
fi

# re-running must not duplicate the appended lines
bash "$INSTALL" >"$SANDBOX/install2.log" 2>&1
n="$(grep -c "include=" "$MPV_DIR/mpv.conf")"
if (( n == 1 )); then ok "idempotent: one include= line"; else bad "duplicated include line ($n)"; fi
s="$(grep -c "input-ipc-server" "$MPV_DIR/mpv.conf")"
if (( s == 1 )); then ok "idempotent: one input-ipc-server line"; else bad "duplicated socket line ($s)"; fi

# ── custom config/mpv.json must drive the included paths (#3) ─────────────────
# OMARCHY_MPV_CONFIG points the installer at a config with a custom
# theme_conf_path / socket_path / keybinding; install.sh must honour all three.
CUSTOM="$(mktemp -d)"
export HOME="$CUSTOM/home"
export XDG_CONFIG_HOME="$CUSTOM/config"
export XDG_STATE_HOME="$CUSTOM/state"
export XDG_RUNTIME_DIR="$CUSTOM/run"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/hypr" "$XDG_STATE_HOME/omarchy/current/theme" "$XDG_RUNTIME_DIR"
cat > "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
dark_background = "#080910"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML
printf -- '-- main\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
cat > "$CUSTOM/mpv.json" <<JSON
{
  "theme_conf_path": "$CUSTOM/custom-theme.conf",
  "socket_path": "$CUSTOM/custom.sock",
  "keybinding": "SUPER + CTRL + K"
}
JSON

OMARCHY_MPV_CONFIG="$CUSTOM/mpv.json" bash "$INSTALL" >"$CUSTOM/install.log" 2>&1
rc=$?
if (( rc == 0 )); then ok "custom-config install.sh exit 0"; else bad "custom-config install.sh exit $rc"; cat "$CUSTOM/install.log"; fi
if [[ -f "$CUSTOM/custom-theme.conf" ]]; then
  ok "custom theme fragment written to the configured path"
else
  bad "custom theme fragment missing"
fi
if grep -qF "include=$CUSTOM/custom-theme.conf" "$XDG_CONFIG_HOME/mpv/mpv.conf"; then
  ok "include= points at the custom theme_conf_path"
else
  bad "include= did not use the custom path"; cat "$XDG_CONFIG_HOME/mpv/mpv.conf"
fi
if grep -qF "input-ipc-server=$CUSTOM/custom.sock" "$XDG_CONFIG_HOME/mpv/mpv.conf"; then
  ok "input-ipc-server= points at the custom socket_path"
else
  bad "input-ipc-server= did not use the custom path"
fi
if grep -q 'o.bind("SUPER + CTRL + K", "mpv: open"' "$XDG_CONFIG_HOME/hypr/mpv-bindings.lua"; then
  ok "installed binding uses the configured keybinding"
else
  bad "installed binding did not use the configured keybinding"
fi
if grep -qF "SUPER + CTRL + K opens it" "$CUSTOM/install.log"; then
  ok "closing hint honours the custom keybinding"
else
  bad "closing hint ignored the custom keybinding"
fi
rm -rf "$CUSTOM"

# ── a pre-existing input-ipc-server line must not disable the plugin (#6) ──────
# A user's own socket path used to make install silently skip adding the
# plugin's socket, leaving `send`/`theme --live` permanently dead.
FOREIGN="$(mktemp -d)"
export HOME="$FOREIGN/home"
export XDG_CONFIG_HOME="$FOREIGN/config"
export XDG_STATE_HOME="$FOREIGN/state"
export XDG_RUNTIME_DIR="$FOREIGN/run"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/mpv" "$XDG_CONFIG_HOME/hypr" \
         "$XDG_STATE_HOME/omarchy/current/theme" "$XDG_RUNTIME_DIR"
cat > "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML
printf -- '-- main\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
printf 'input-ipc-server=/tmp/myown-mpv.sock\n' > "$XDG_CONFIG_HOME/mpv/mpv.conf"

bash "$INSTALL" >"$FOREIGN/install.log" 2>&1
rc=$?
if (( rc == 0 )); then ok "foreign-socket install.sh exit 0"; else bad "foreign-socket install.sh exit $rc"; cat "$FOREIGN/install.log"; fi
if grep -qF "input-ipc-server=$XDG_RUNTIME_DIR/omarchy-mpv.sock" "$XDG_CONFIG_HOME/mpv/mpv.conf"; then
  ok "plugin socket added despite a pre-existing socket line"
else
  bad "plugin socket was NOT added"; cat "$XDG_CONFIG_HOME/mpv/mpv.conf"
fi
if grep -qF "# omarchy-mpv: superseded input-ipc-server=/tmp/myown-mpv.sock" "$XDG_CONFIG_HOME/mpv/mpv.conf"; then
  ok "pre-existing socket line reconciled (commented, not lost)"
else
  bad "pre-existing socket line was not reconciled"; cat "$XDG_CONFIG_HOME/mpv/mpv.conf"
fi
if grep -q "commented it out" "$FOREIGN/install.log"; then
  ok "install warned about the pre-existing socket line"
else
  bad "no warning about the pre-existing socket line"
fi
rm -rf "$FOREIGN"

# ── a non-dict config must not kill the installer under set -e (#7) ───────────
# config/mpv.json containing `true` used to make load_config raise TypeError;
# install.sh's unguarded `bindings` call then aborted the install.
NONDICT="$(mktemp -d)"
export HOME="$NONDICT/home"
export XDG_CONFIG_HOME="$NONDICT/config"
export XDG_STATE_HOME="$NONDICT/state"
export XDG_RUNTIME_DIR="$NONDICT/run"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/hypr" "$XDG_STATE_HOME/omarchy/current/theme" "$XDG_RUNTIME_DIR"
cat > "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML
printf -- '-- main\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
printf 'true\n' > "$NONDICT/mpv.json"
OMARCHY_MPV_CONFIG="$NONDICT/mpv.json" bash "$INSTALL" >"$NONDICT/install.log" 2>&1
rc=$?
if (( rc == 0 )); then ok "non-dict config install.sh exit 0"; else bad "non-dict config install.sh exit $rc"; cat "$NONDICT/install.log"; fi
if grep -q "Done." "$NONDICT/install.log"; then
  ok "non-dict config still reaches the Done. line (no half-applied install)"
else
  bad "non-dict config aborted before Done."; cat "$NONDICT/install.log"
fi
rm -rf "$NONDICT"

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
