-- ─────────────────────────────────────────────────────────────────────────────
--  Flow Shell: Layer Rules & Window Rules
--  Sourced automatically by hyprland.conf. All Flow shell keybinds live in
--  hyprland/keybinds.lua and target the same IPC surface (`qs -c $qsConfig`).
--  The shell itself is launched by hyprland/execs.lua.
-- ─────────────────────────────────────────────────────────────────────────────

hl.config({
    layerrule = {
        "blur, quickshell:.*",
        "ignore_alpha 0.79, quickshell:.*",
        "blur, notifications",
        "ignore_alpha 0.69, notifications",
        "blur, launcher",
        "ignore_alpha 0.5, launcher",
        "no_anim, overview",
        "blur, session",

        -- Instantly show region tools
        "no_anim, quickshell:regionSelector",
        "blur off, quickshell:regionSelector",
        "no_anim, quickshell:recordingMarker",
        "blur off, quickshell:recordingMarker"
    }
})

-- Flow Panels (Native Floating)
hl.window_rule({ match = { title = "^(Settings)$" },       float = 1, center = 1, border_size = 0 })
hl.window_rule({ match = { title = "^(System Monitor)$" },  float = 1, center = 1, border_size = 0 })
hl.window_rule({ match = { title = "^(Welcome to Flow)$" }, float = 1, center = 1, border_size = 0 })
