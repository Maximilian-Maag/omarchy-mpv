#!/bin/bash
# Round-trip test for `install.sh --uninstall`.
#
# The contract: an install followed by an uninstall leaves the user's own config
# byte-identical (sha256) and removes EXACTLY what the install added — the CLI
# symlink, the theme-set hook, the generated theme fragment, the keybinding
# module and the require block, and the `include=` / `input-ipc-server=` lines in
# mpv.conf — while leaving anything that is not ours alone.
#
# Hermetic: a throwaway HOME/XDG with stubbed omarchy/sudo, and the CLI symlinked
# into the sandbox (OMARCHY_MPV_BIN) so no root is involved.
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
export OMARCHY_MPV_BIN="$SANDBOX/bin"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d" \
         "$XDG_STATE_HOME/omarchy/current/theme" "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME" "$OMARCHY_MPV_BIN"
cat > "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
dark_background = "#080910"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML

# Stubbed omarchy/sudo first on PATH; a real python3 (for the CLI) after them.
STUB="$SANDBOX/stub"; mkdir -p "$STUB"
export PATH="$STUB:/usr/bin:/bin:/usr/local/bin"
printf '#!/bin/bash\nexit 0\n' > "$STUB/omarchy"
printf '#!/bin/bash\nexit 0\n' > "$STUB/sudo"
chmod +x "$STUB/omarchy" "$STUB/sudo"

MPV_CONF="$XDG_CONFIG_HOME/mpv/mpv.conf"
HYPR="$XDG_CONFIG_HOME/hypr/hyprland.lua"
BINDINGS="$XDG_CONFIG_HOME/hypr/mpv-bindings.lua"
THEME_CONF="$XDG_CONFIG_HOME/mpv/omarchy-theme.conf"
HOOK="$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d/mpv-theme-set"
CLI_LINK="$OMARCHY_MPV_BIN/omarchy-mpv"

sha() { sha256sum "$1" | cut -d' ' -f1; }
# (re)create the user's own config and the hook a prior install would have left.
setup_user() {
  mkdir -p "$(dirname "$MPV_CONF")"
  printf '# my precious config\nvo=gpu\n' > "$MPV_CONF"
  printf -- '-- main config\nlocal monitors = {}\n' > "$HYPR"
  printf '#!/bin/bash\n' > "$HOOK"
}

echo "install/uninstall round-trip"

# ── 1. The happy path: byte-identity of the user's own files. ─────────────────
setup_user
before_conf="$(sha "$MPV_CONF")"
before_hypr="$(sha "$HYPR")"

if bash "$INSTALL" >"$SANDBOX/install.log" 2>&1; then ok "install exit 0"; else bad "install failed"; cat "$SANDBOX/install.log"; fi
# The install really did add the things the uninstall must reverse.
if [[ -L "$CLI_LINK" ]]; then ok "install symlinked the CLI"; else bad "no CLI symlink"; fi
if grep -qF "include=" "$MPV_CONF"; then ok "install added include="; else bad "no include= added"; fi
if grep -qF "input-ipc-server=" "$MPV_CONF"; then ok "install added input-ipc-server="; else bad "no socket line added"; fi
if [[ -f "$THEME_CONF" ]]; then ok "install generated the theme fragment"; else bad "no theme fragment"; fi
if [[ -f "$BINDINGS" ]]; then ok "install wrote the bindings module"; else bad "no bindings module"; fi
if grep -qF 'require("hypr.mpv-bindings")' "$HYPR"; then ok "install wired the require line"; else bad "no require line"; fi

if bash "$INSTALL" --uninstall >"$SANDBOX/uninstall.log" 2>&1; then ok "uninstall exit 0"; else bad "uninstall failed"; cat "$SANDBOX/uninstall.log"; fi
if [[ "$(sha "$MPV_CONF")" == "$before_conf" ]]; then ok "mpv.conf is byte-identical after the round-trip"; else bad "mpv.conf changed"; diff <(echo "$before_conf") <(sha "$MPV_CONF"); cat "$MPV_CONF"; fi
if [[ "$(sha "$HYPR")" == "$before_hypr" ]]; then ok "hyprland.lua is byte-identical after the round-trip"; else bad "hyprland.lua changed"; cat "$HYPR"; fi
if [[ "$(grep -c -- '-- omarchy-mpv' "$HYPR")" == 0 ]]; then ok "no marker comment left in hyprland.lua"; else bad "a marker was left behind"; cat "$HYPR"; fi
if [[ "$(grep -c '# omarchy-mpv' "$MPV_CONF")" == 0 ]]; then ok "no marker comment left in mpv.conf"; else bad "a marker was left in mpv.conf"; cat "$MPV_CONF"; fi
# …and each installed artifact is gone.
if [[ ! -e "$CLI_LINK" ]]; then ok "removed the CLI symlink"; else bad "CLI symlink survived"; fi
if [[ ! -e "$BINDINGS" ]]; then ok "removed the bindings module"; else bad "bindings module survived"; fi
if [[ ! -e "$THEME_CONF" ]]; then ok "removed the theme fragment"; else bad "theme fragment survived"; fi
if [[ ! -e "$HOOK" ]]; then ok "removed the theme-set hook"; else bad "hook survived"; fi

# ── 2. A second cycle stays byte-identical (no marker accumulation). ──────────
bash "$INSTALL" >/dev/null 2>&1
bash "$INSTALL" --uninstall >/dev/null 2>&1
if [[ "$(sha "$MPV_CONF")" == "$before_conf" && "$(sha "$HYPR")" == "$before_hypr" ]]; then
  ok "a second install/uninstall cycle stays byte-identical"
else
  bad "a second cycle changed the user's config"; cat "$MPV_CONF"; cat "$HYPR"
fi

# ── 3. A hand-added require line (no marker) is removed, its neighbour kept. ──
printf 'local monitors = {}\nrequire("hypr.mpv-bindings")\n' > "$HYPR"
bash "$INSTALL" --uninstall >/dev/null 2>&1
if [[ "$(cat "$HYPR")" == 'local monitors = {}' ]]; then
  ok "a hand-added require line is removed without eating the line above it"
else
  bad "hand-added require line handling is wrong"; cat "$HYPR"
fi

# ── 4. The user's own input-ipc-server survives (and is restored verbatim). ───
printf '# mine\ninput-ipc-server=/tmp/my-own.sock\n' > "$MPV_CONF"
printf -- '-- main\n' > "$HYPR"
before_conf="$(sha "$MPV_CONF")"
bash "$INSTALL" >/dev/null 2>&1
if grep -qF '# omarchy-mpv: superseded input-ipc-server=/tmp/my-own.sock' "$MPV_CONF"; then
  ok "install reconciled a foreign socket line instead of shadowing it"
else
  bad "foreign socket line was not reconciled"; cat "$MPV_CONF"
fi
bash "$INSTALL" --uninstall >/dev/null 2>&1
if [[ "$(sha "$MPV_CONF")" == "$before_conf" ]]; then
  ok "a user's own input-ipc-server line is restored byte-identically"
else
  bad "the user's own socket line was not restored"; cat "$MPV_CONF"
fi

# ── 5. A file the install created is removed (not left empty behind). ─────────
rm -f "$MPV_CONF"
rm -rf "$(dirname "$MPV_CONF")"
printf -- '-- main\n' > "$HYPR"
bash "$INSTALL" >/dev/null 2>&1
if [[ -f "$MPV_CONF" ]]; then ok "install created mpv.conf"; else bad "install did not create mpv.conf"; fi
bash "$INSTALL" --uninstall >/dev/null 2>&1
if [[ ! -e "$MPV_CONF" ]]; then ok "a created mpv.conf is removed again"; else bad "created mpv.conf was left behind"; cat "$MPV_CONF"; fi

# ── 6. A foreign symlink at the CLI path is left alone. ───────────────────────
printf -- '-- main\n' > "$HYPR"
ln -sfn /bin/true "$CLI_LINK"
out="$(bash "$INSTALL" --uninstall 2>&1)"; rc=$?
if (( rc == 0 )); then ok "an uninstall over a foreign symlink exits 0"; else bad "uninstall exit $rc"; fi
if [[ -L "$CLI_LINK" ]] && [[ "$(readlink "$CLI_LINK")" == "/bin/true" ]]; then
  ok "a foreign symlink at the CLI path is left alone"
else
  bad "a foreign symlink was removed"; ls -l "$CLI_LINK" 2>&1
fi
if [[ $out == *"not a link into this checkout"* ]]; then ok "and the uninstall says why"; else bad "no reason given: $out"; fi
rm -f "$CLI_LINK"

# ── 7. Uninstalling nothing is not an error. ──────────────────────────────────
bash "$INSTALL" --uninstall >/dev/null 2>&1
if (( $? == 0 )); then ok "uninstalling an empty machine succeeds"; else bad "uninstalling nothing failed"; fi

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
