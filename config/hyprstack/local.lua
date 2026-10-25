-- Optional local settings. This file is preserved during updates.
hl.config({ input = { kb_layout = "us,ru", kb_options = "grp:alt_shift_toggle" } })
hl.config({ xwayland = { force_zero_scaling = true } })
hl.on("hyprland.start", function() hl.exec_cmd("sleep 5 && bash " .. os.getenv("HOME") .. "/bar-hover.sh") end)
-- hl.config({ debug = { damage_tracking = 0 } })  -- выключено: перерисовывало оба монитора целиком каждый кадр
hl.on("hyprland.start", function() hl.exec_cmd("sleep 2 && hyprctl setcursor Volantes-Dark 24") end)
hl.on("hyprland.start", function() hl.exec_cmd("sleep 3 && qs -c desktop-widgets --no-duplicate") end)
-- Super+Shift+S: скриншот области сразу в буфер обмена, без окна swappy
hl.unbind("SUPER + SHIFT + S")
hl.bind("SUPER + SHIFT + S", hl.dsp.global("hyprstack:screenshotFreezeClip"))
-- Курсор не уходит на соседний монитор во время игры (Super+Ctrl+G — вкл/выкл)
dofile(os.getenv("HOME") .. "/.config/hyprstack/game-cursor-lock.lua")
