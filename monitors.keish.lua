-- Optional local settings. This file is preserved during updates.

-- Экран ноутбука слева (2560x1440 при scale 1.6 = 1600 логических пикселей в ширину)
hl.monitor({
    output   = "eDP-1",
    mode     = "2560x1440@165",
    position = "0x126", -- по центру монитора по вертикали: (1152-900)/2
    scale    = 1.6,
})

-- Внешний монитор XT27N1 по HDMI (NVIDIA), справа от ноутбука.
-- scale 1.25 → 2048x1152 логических пикселей
-- preferred выбирал 60 Гц, а он умеет 144
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "2560x1440@144",
    position = "1600x0",
    scale    = 1.25,
})

-- В режиме dGPU (BIOS) панель ноутбука подключена к NVIDIA и называется eDP-2
hl.monitor({
    output   = "eDP-2",
    mode     = "2560x1440@165",
    position = "0x126",
    scale    = 1.6,
})

-- Тот же XT27N1 через USB-C → DisplayPort (порты USB-C идут на NVIDIA: DP-1/DP-2)
for _, output in ipairs({ "DP-1", "DP-2" }) do
    hl.monitor({
        output   = output,
        mode     = "2560x1440@180",
        position = "1600x0",
        scale    = 1.25,
    })
end
