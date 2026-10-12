#!/bin/bash
# e2e: generate an mpv theme fragment from a synthetic applied theme, then prove
# it is accepted by a REAL headless mpv and that `send` round-trips over mpv's
# JSON IPC socket. The user's real mpv session is never touched (a throwaway
# socket and a private XDG root are used).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/bin/omarchy-mpv"
WORK="$(mktemp -d)"
SOCK="$WORK/mpv.sock"
MPV_PID=""
cleanup() {
  if [[ -n "$MPV_PID" ]]; then kill "$MPV_PID" 2>/dev/null; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

export HOME="$WORK/home"
export XDG_STATE_HOME="$WORK/state"
export XDG_CONFIG_HOME="$WORK/config"
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
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

"$CLI" theme
CONF="$XDG_CONFIG_HOME/mpv/omarchy-theme.conf"
if [[ ! -f "$CONF" ]]; then
  echo "e2e: FAILED — theme fragment not generated" >&2
  exit 1
fi

for colour in "#82FB9C" "#0B0C16" "#ddf7ff" "#080910"; do
  if ! grep -q "$colour" "$CONF"; then
    echo "e2e: FAILED — generated fragment is missing theme colour $colour" >&2
    exit 1
  fi
done

if ! command -v mpv >/dev/null 2>&1; then
  echo "e2e: SKIPPED — mpv is not installed on this host" >&2
  exit 0
fi

# Launch a real, headless mpv that loads the generated fragment and exposes IPC.
mpv --no-config --include="$CONF" --no-video --idle=yes --vo=null --ao=null \
    --input-ipc-server="$SOCK" >"$WORK/mpv.log" 2>&1 &
MPV_PID=$!

for _ in $(seq 1 50); do
  [[ -S "$SOCK" ]] && break
  sleep 0.1
done
if [[ ! -S "$SOCK" ]]; then
  echo "e2e: FAILED — mpv did not expose an IPC socket" >&2
  cat "$WORK/mpv.log" >&2
  exit 1
fi

# The generated fragment must not have produced a config error.
if grep -qiE 'error parsing|unknown option|invalid' "$WORK/mpv.log"; then
  echo "e2e: FAILED — mpv rejected a line from the generated fragment" >&2
  cat "$WORK/mpv.log" >&2
  exit 1
fi

# `send` must round-trip a real command over the socket.
if ! "$CLI" --socket "$SOCK" send toggle; then
  echo "e2e: FAILED — send toggle did not round-trip" >&2
  exit 1
fi
if ! "$CLI" --socket "$SOCK" send volume 55; then
  echo "e2e: FAILED — send volume 55 did not round-trip" >&2
  exit 1
fi
value="$("$CLI" --socket "$SOCK" send volume)"
if [ "$value" != "55.0" ]; then
  echo "e2e: FAILED — expected volume 55.0 back, got '$value'" >&2
  exit 1
fi

# `theme --live` must push the colours to the running mpv over IPC.
if ! "$CLI" --socket "$SOCK" theme --live; then
  echo "e2e: FAILED — theme --live failed" >&2
  exit 1
fi

echo "e2e: ok — $(mpv --version | head -1) accepted the fragment; send round-tripped (volume=$value)"
exit 0
