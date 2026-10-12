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

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
