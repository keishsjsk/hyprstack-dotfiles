# hyprstack-dotfiles

Мой Hyprland 0.56 + [hyprstack](https://github.com/hase9awa/hyprstack-shell) с правками:
плавающие острова сверху, иконки на рабочем столе, виджеты (`desktop-widgets`),
горизонтальные рабочие столы, Alt+Tab поверх полноэкранных окон, блокировка курсора в играх,
Bluetooth-агент, уведомления о батарее, иконки Material Symbols Sharp, курсор Volantes-Dark.

## Установка (Arch / CachyOS)

Из TTY или из текущего сеанса Hyprland:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/__REPO__/main/install.sh)
```

Скрипт ставит пакеты, собирает hyprstack (зафиксированная версия), переносит старые
`~/.config/{hypr,hyprstack,quickshell,uwsm,fontconfig,kitty}` в `~/dotfiles-backup-*`,
копирует конфиги и накладывает правки на оболочку. Потом перезайди в Hyprland.

Опции: `SKIP_DEPS=1` — без pacman, `SKIP_BUILD=1` — не пересобирать hyprstack,
`MONITORS=keish` — взять мои мониторы (`monitors.keish.lua`), `JOBS=4` — потоки сборки.

Мониторы: по умолчанию сохраняется твой старый `~/.config/hyprstack/monitors.lua`
(или создаётся пустой). Пример — `monitors.keish.lua`.

## Структура

- `config/` → `~/.config`
- `shell-overlay/` → поверх `~/.local/share/hyprstack/shell` (изменённые файлы оболочки)
- `local/bin/` → `~/.local/bin` (bt-agent, battery-warn)
- `icons/` — курсор Volantes-Dark, `wallpapers/` — обои

## Обновить мой репозиторий из текущей системы

```bash
~/dotfiles/sync.sh && git -C ~/dotfiles commit -am "update" && git -C ~/dotfiles push
```
