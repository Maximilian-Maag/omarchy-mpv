-- Hyprland keybindings added by omarchy-mpv.
-- Sourced from hyprland.lua by install.sh (require("hypr.mpv-bindings")).
--
-- This is a TEMPLATE: `omarchy-mpv bindings` (and install.sh) substitute the
-- configured `keybinding` from config/mpv.json for the {{KEYBINDING}} token
-- below, so editing the config changes the installed binding. The file itself
-- is valid Lua (the token is just a string), but do not source it directly.
--
-- Omarchy's own default bindings already own the bare XF86Audio* media keys
-- (they drive the system media player). To avoid clobbering those, mpv's
-- transport is bound behind SUPER, so the two coexist.
--
-- The 'open mpv' chord is deliberately NOT one Omarchy ships: its former
-- SUPER + SHIFT + ALT + M collided with Omarchy's built-in 'Music TUI' binding
-- (default/hypr/bindings/applications.lua). The regression suite pins the
-- configured chord against the installed Omarchy defaults.

hl.unbind("SUPER + XF86AudioPlay")
hl.unbind("SUPER + XF86AudioNext")
hl.unbind("SUPER + XF86AudioPrev")
hl.unbind("SUPER + XF86AudioStop")

o.bind("SUPER + XF86AudioPlay", "mpv: play/pause", "omarchy-mpv send toggle", { locked = true })
o.bind("SUPER + XF86AudioNext", "mpv: next", "omarchy-mpv send next", { locked = true })
o.bind("SUPER + XF86AudioPrev", "mpv: previous", "omarchy-mpv send prev", { locked = true })
o.bind("SUPER + XF86AudioStop", "mpv: stop", "omarchy-mpv send stop", { locked = true })
o.bind("{{KEYBINDING}}", "mpv: open", "mpv --idle=yes --force-window=yes")
