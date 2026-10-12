-- Hyprland keybindings added by omarchy-mpv.
-- Sourced from hyprland.lua by install.sh (require("hypr.mpv-bindings")).
--
-- Omarchy's own default bindings already own the bare XF86Audio* media keys
-- (they drive the system media player). To avoid clobbering those, mpv's
-- transport is bound behind SUPER, so the two coexist.

hl.unbind("SUPER + XF86AudioPlay")
hl.unbind("SUPER + XF86AudioNext")
hl.unbind("SUPER + XF86AudioPrev")
hl.unbind("SUPER + XF86AudioStop")
hl.unbind("SUPER + SHIFT + ALT + M")

o.bind("SUPER + XF86AudioPlay", "mpv: play/pause", "omarchy-mpv send toggle", { locked = true })
o.bind("SUPER + XF86AudioNext", "mpv: next", "omarchy-mpv send next", { locked = true })
o.bind("SUPER + XF86AudioPrev", "mpv: previous", "omarchy-mpv send prev", { locked = true })
o.bind("SUPER + XF86AudioStop", "mpv: stop", "omarchy-mpv send stop", { locked = true })
o.bind("SUPER + SHIFT + ALT + M", "mpv: open", "mpv --idle=yes --force-window=yes")
