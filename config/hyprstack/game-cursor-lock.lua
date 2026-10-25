-- Не даёт курсору уходить на соседний монитор, пока активна игра.
-- Игра = класс из game_classes (в любом режиме) или любое окно в настоящем
-- fullscreen, кроме браузеров/плееров. Super+Ctrl+G — вкл/выкл блокировку.

local game_classes = { "^steam_app_", "^gamescope$", "minecraft", "^lutris", "%.exe$" }
local not_games = { "firefox", "chrom", "mpv", "vlc", "celluloid", "kitty", "spotify" }

local enabled = true
local timer
local locked_window

local function matches(class, patterns)
    class = (class or ""):lower()
    for _, p in ipairs(patterns) do
        if class:find(p) then return true end
    end
    return false
end

local function is_game(w)
    if not w then return false end
    if matches(w.class, game_classes) then return true end
    return w.fullscreen == 2 and not matches(w.class, not_games)
end

local function clamp()
    local ok, w = pcall(function() return locked_window and locked_window.mapped and locked_window end)
    if not ok or not w then return end
    local m = w.monitor
    local p = hl.get_cursor_pos()
    if not m or not p then return end
    local s = m.scale or 1
    local x0, y0 = m.x, m.y
    local x1, y1 = m.x + m.width / s - 1, m.y + m.height / s - 1
    if m.transform == 1 or m.transform == 3 or m.transform == 5 or m.transform == 7 then
        x1, y1 = m.x + m.height / s - 1, m.y + m.width / s - 1
    end
    local x = math.min(math.max(p.x, x0), x1)
    local y = math.min(math.max(p.y, y0), y1)
    if x ~= p.x or y ~= p.y then
        hl.dispatch(hl.dsp.cursor.move({ x = x, y = y }))
    end
end

local function update()
    local w = hl.get_active_window()
    local lock = enabled and is_game(w)
    locked_window = lock and w or nil
    if lock and not timer then
        timer = hl.timer(clamp, { timeout = 2, type = "repeat" })
    elseif not lock and timer then
        timer:set_enabled(false)
        timer = nil
    end
end

hl.on("window.active", update)
hl.on("window.fullscreen", update)
hl.on("window.close", function() hl.timer(update, { timeout = 1, type = "oneshot" }) end)

hl.bind("SUPER + CTRL + G", function()
    enabled = not enabled
    update()
    hl.exec_cmd("notify-send -a Hyprland -t 1500 'Курсор в играх' '" ..
        (enabled and "Заперт на мониторе игры" or "Свободен") .. "'")
end, { description = "Games: Toggle cursor lock to game monitor" })

update()
