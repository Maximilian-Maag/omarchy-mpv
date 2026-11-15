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
rm -rf "$CUSTOM"

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
