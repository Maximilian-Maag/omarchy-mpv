#!/bin/bash
# omarchy-mpv install script. Run once after cloning, or re-run to update.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional config override, passed through to every CLI invocation. The shell
# tests use it to prove a custom config/mpv.json is honoured; a normal user runs
# the installer bare and the plugin's own config/mpv.json is used.
CLI_ARGS=()
if [[ -n "${OMARCHY_MPV_CONFIG:-}" ]]; then
  CLI_ARGS=(--config "$OMARCHY_MPV_CONFIG")
fi

echo "omarchy-mpv: installing from $PLUGIN_DIR"

# ── 1. Validate the plugin ────────────────────────────────────────────────────
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$PLUGIN_DIR" && echo "  manifest OK."
fi

# ── 2. Put the CLI on PATH (symlink, so git pull keeps it current) ────────────
BIN_SRC="$PLUGIN_DIR/bin/omarchy-mpv"
BIN_DEST="/usr/local/bin/omarchy-mpv"
chmod +x "$BIN_SRC"
if [[ -L "$BIN_DEST" ]] && [[ "$(readlink -f "$BIN_DEST")" == "$(readlink -f "$BIN_SRC")" ]]; then
  echo "  omarchy-mpv already on PATH."
elif (( EUID == 0 )); then
  ln -sf "$BIN_SRC" "$BIN_DEST" && echo "  Installed $BIN_DEST."
elif command -v sudo >/dev/null 2>&1; then
  sudo ln -sf "$BIN_SRC" "$BIN_DEST" && echo "  Installed $BIN_DEST."
else
  echo "  WARNING: no sudo — add $BIN_SRC to PATH manually."
fi

# ── 3. Generate the theme fragment now ────────────────────────────────────────
"$BIN_SRC" "${CLI_ARGS[@]}" theme || echo "  WARNING: no applied theme yet — run 'omarchy-mpv theme' later."

# ── 4. Make the user's mpv.conf include our fragment + expose the IPC socket ──
# Both paths come from the CLI (config/mpv.json's theme_conf_path / socket_path),
# so a custom path is honoured rather than silently ignored. Nothing the user
# wrote is ever destroyed: both lines are appended at most once, each guarded.
MPV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mpv"
MPV_CONF="$MPV_DIR/mpv.conf"
PATHS="$("$BIN_SRC" "${CLI_ARGS[@]}" paths 2>/dev/null || true)"
THEME_CONF="$(printf '%s\n' "$PATHS" | sed -n 's/^theme_conf=//p')"
SOCKET_PATH="$(printf '%s\n' "$PATHS" | sed -n 's/^socket=//p')"
if [[ -z "$THEME_CONF" || -z "$SOCKET_PATH" ]]; then
  echo "  WARNING: could not read paths from the CLI — using the built-in defaults."
  THEME_CONF="$MPV_DIR/omarchy-theme.conf"
  SOCKET_PATH="${XDG_RUNTIME_DIR:-/tmp}/omarchy-mpv.sock"
fi
THEME_LINE="include=$THEME_CONF"
SOCKET_LINE="input-ipc-server=$SOCKET_PATH"
mkdir -p "$MPV_DIR"
if [[ ! -f "$MPV_CONF" ]]; then
  printf '# omarchy-mpv integration\n%s\n%s\n' "$THEME_LINE" "$SOCKET_LINE" > "$MPV_CONF"
  echo "  Created $MPV_CONF."
else
  if grep -qF "include=$THEME_CONF" "$MPV_CONF" || grep -q "omarchy-theme.conf" "$MPV_CONF"; then
    echo "  mpv.conf already includes $THEME_CONF."
  else
    printf '\n# omarchy-mpv theme\n%s\n' "$THEME_LINE" >> "$MPV_CONF"
    echo "  Added include= to $MPV_CONF (your config is otherwise untouched)."
  fi
  if grep -qF "input-ipc-server=$SOCKET_PATH" "$MPV_CONF"; then
    echo "  mpv.conf already exposes the plugin's IPC socket."
  else
    # The guard is path-aware: only the plugin's exact socket line counts as
    # done. A pre-existing line at some other path would otherwise shadow ours
    # (anchor grep matches ANY input-ipc-server), leaving `send`/`theme --live`
    # permanently dead while install reported success (#6). Reconcile it by
    # commenting it out (its text is preserved) and add ours last.
    if grep -qE '^[[:space:]]*input-ipc-server=' "$MPV_CONF"; then
      sed -i -E 's|^([[:space:]]*input-ipc-server=.*)|# omarchy-mpv: superseded \1|' "$MPV_CONF"
      echo "  WARNING: $MPV_CONF already set input-ipc-server — commented it out so the plugin's socket is the active one."
    fi
    printf '\n# omarchy-mpv IPC socket\n%s\n' "$SOCKET_LINE" >> "$MPV_CONF"
    echo "  Added input-ipc-server= to $MPV_CONF."
    if ! grep -qF "$SOCKET_LINE" "$MPV_CONF"; then
      echo "  WARNING: could not add $SOCKET_LINE to $MPV_CONF — add it by hand so 'send' and 'theme --live' work."
    fi
  fi
fi

# ── 5. Theme-set hook (uniquely named to avoid basename collisions) ───────────
chmod +x "$PLUGIN_DIR/hooks/mpv-theme-set"
if command -v omarchy >/dev/null 2>&1; then
  omarchy hook install theme-set "$PLUGIN_DIR/hooks/mpv-theme-set"
  echo "  Installed theme-set hook (as mpv-theme-set)."
fi

# ── 6. Wire media-key bindings into Hyprland (rendered from config) ───────────
HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_CONFIG_DIR/hyprland.lua"
if [[ -f "$HYPR_MAIN" ]]; then
  # The CLI renders bin/bindings.lua with the configured `keybinding`, so the
  # installed module always matches config/mpv.json.
  "$BIN_SRC" "${CLI_ARGS[@]}" bindings || echo "  WARNING: could not install the keybindings module."
else
  echo "  WARNING: $HYPR_MAIN not found — add: require(\"hypr.mpv-bindings\")"
fi

# Print the chord that was actually installed, read back from the CLI (the same
# value `paths` reports and `bindings` rendered), so the hint cannot drift from
# config/mpv.json (#5).
KEYBINDING="$(printf '%s\n' "$PATHS" | sed -n 's/^keybinding=//p')"
if [[ -z "$KEYBINDING" ]]; then
  KEYBINDING="SUPER + SHIFT + ALT + V"
fi

echo ""
echo "Done. Try:  omarchy-mpv theme   /   omarchy-mpv status   /   omarchy-mpv send toggle"
echo "Media keys: Super + Play/Next/Prev/Stop drive mpv; $KEYBINDING opens it."
