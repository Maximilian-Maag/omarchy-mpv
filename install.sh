#!/bin/bash
# omarchy-mpv install script. Run once after cloning, or re-run to update.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
"$BIN_SRC" theme || echo "  WARNING: no applied theme yet — run 'omarchy-mpv theme' later."

# ── 4. Make the user's mpv.conf include our fragment + expose the IPC socket ──
# Nothing the user wrote is ever destroyed: both lines are appended at most once,
# each guarded by a grep.
MPV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mpv"
MPV_CONF="$MPV_DIR/mpv.conf"
THEME_LINE="include=$MPV_DIR/omarchy-theme.conf"
SOCKET_LINE="input-ipc-server=${XDG_RUNTIME_DIR:-/tmp}/omarchy-mpv.sock"
mkdir -p "$MPV_DIR"
if [[ ! -f "$MPV_CONF" ]]; then
  printf '# omarchy-mpv integration\n%s\n%s\n' "$THEME_LINE" "$SOCKET_LINE" > "$MPV_CONF"
  echo "  Created $MPV_CONF."
else
  if grep -q "omarchy-theme.conf" "$MPV_CONF"; then
    echo "  mpv.conf already includes omarchy-theme.conf."
  else
    printf '\n# omarchy-mpv theme\n%s\n' "$THEME_LINE" >> "$MPV_CONF"
    echo "  Added include= to $MPV_CONF (your config is otherwise untouched)."
  fi
  if grep -q "input-ipc-server" "$MPV_CONF"; then
    echo "  mpv.conf already exposes an IPC socket."
  else
    printf '\n# omarchy-mpv IPC socket\n%s\n' "$SOCKET_LINE" >> "$MPV_CONF"
    echo "  Added input-ipc-server= to $MPV_CONF."
  fi
fi

# ── 5. Theme-set hook (uniquely named to avoid basename collisions) ───────────
chmod +x "$PLUGIN_DIR/hooks/mpv-theme-set"
if command -v omarchy >/dev/null 2>&1; then
  omarchy hook install theme-set "$PLUGIN_DIR/hooks/mpv-theme-set"
  echo "  Installed theme-set hook (as mpv-theme-set)."
fi

# ── 6. Wire media-key bindings into Hyprland ──────────────────────────────────
HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_CONFIG_DIR/hyprland.lua"
if [[ -f "$HYPR_MAIN" ]]; then
  cp "$PLUGIN_DIR/bin/bindings.lua" "$HYPR_CONFIG_DIR/mpv-bindings.lua"
  if ! grep -q "mpv-bindings" "$HYPR_MAIN"; then
    printf '\n-- omarchy-mpv keybindings\nrequire("hypr.mpv-bindings")\n' >> "$HYPR_MAIN"
    echo "  Wired keybindings into $HYPR_MAIN"
  else
    echo "  Keybindings already wired (updated)."
  fi
else
  echo "  WARNING: $HYPR_MAIN not found — add: require(\"hypr.mpv-bindings\")"
fi

echo ""
echo "Done. Try:  omarchy-mpv theme   /   omarchy-mpv status   /   omarchy-mpv send toggle"
echo "Media keys: Super + Play/Next/Prev/Stop drive mpv; Super+Shift+Alt+M opens it."
