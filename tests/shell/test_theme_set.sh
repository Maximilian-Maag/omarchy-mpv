#!/bin/bash
# Shell tests for hooks/mpv-theme-set — hermetic (throwaway HOME/XDG).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/hooks/mpv-theme-set"
pass=0; fail=0
ok()  { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }

setup() {
  SANDBOX="$(mktemp -d)"
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
}

teardown() { rm -rf "$SANDBOX"; }
CONF() { printf '%s\n' "$XDG_CONFIG_HOME/mpv/omarchy-theme.conf"; }

# 1. plugin found via the override only -> conf generated (kills the -z PLUGIN -> -n mutation)
setup
export OMARCHY_MPV_DIR="$ROOT"
bash "$HOOK" "Hackerman"; rc=$?
if [[ -f "$(CONF)" ]]; then ok "conf generated from the applied theme"; else bad "no conf written"; fi
if (( rc == 0 )); then ok "hook exit 0"; else bad "hook exit $rc"; fi
teardown

# 2. empty theme name -> no-op (kills the -z THEME mutation)
setup
export OMARCHY_MPV_DIR="$ROOT"
bash "$HOOK" ""; rc=$?
if [[ ! -e "$(CONF)" ]]; then ok "empty theme writes nothing"; else bad "empty theme generated a conf"; fi
if (( rc == 0 )); then ok "empty theme exit 0"; else bad "empty theme exit $rc"; fi
teardown

# 3. plugin not found -> graceful no-op
setup
export OMARCHY_MPV_DIR="$SANDBOX/nope"
bash "$HOOK" "Hackerman"; rc=$?
if (( rc == 0 )); then ok "missing plugin exit 0"; else bad "missing plugin exit $rc"; fi
if [[ ! -e "$(CONF)" ]]; then ok "missing plugin writes nothing"; else bad "wrote without a plugin"; fi
teardown

# 4. self-location fallback (kills the && -> || and -n -> -z mutations in find_plugin)
setup
mkdir -p "$HOME/Work"
ln -s "$ROOT" "$HOME/Work/omarchy-mpv"
export OMARCHY_MPV_DIR="$SANDBOX/emptydir"
mkdir -p "$OMARCHY_MPV_DIR"
bash "$HOOK" "Hackerman"
if [[ -f "$(CONF)" ]]; then ok "fell back to the dev checkout"; else bad "did not self-locate"; fi
teardown

# 5. a failing CLI must not abort the hook
setup
export OMARCHY_MPV_DIR="$ROOT"
rm -f "$XDG_STATE_HOME/omarchy/current/theme/colors.toml"
bash "$HOOK" "Hackerman"; rc=$?
if (( rc == 0 )); then ok "hook survives a CLI failure"; else bad "CLI failure aborted the hook (exit $rc)"; fi
teardown

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
