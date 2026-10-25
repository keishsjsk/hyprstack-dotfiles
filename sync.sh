#!/usr/bin/env bash
# Собирает текущие настройки системы обратно в репозиторий.
set -euo pipefail
D=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S=${XDG_DATA_HOME:-$HOME/.local/share}/hyprstack/shell
U=${XDG_CACHE_HOME:-$HOME/.cache}/keish-dotfiles/hyprstack-shell/shell
[ -d "$U" ] || U=$HOME/hyprstack-shell/shell
rs() { rsync -a --delete --exclude='*.bak*' --exclude='*.orig' "$@"; }
rs --exclude=gpu ~/.config/hypr "$D/config/"
rs --exclude=patches --exclude=monitors.lua ~/.config/hyprstack "$D/config/"
rs ~/.config/quickshell ~/.config/uwsm ~/.config/fontconfig ~/.config/kitty "$D/config/"
cp ~/.config/hyprstack/monitors.lua "$D/monitors.keish.lua"
cp ~/.config/systemd/user/{bt-agent,battery-warn}.service "$D/config/systemd/user/"
cp ~/.local/bin/{bt-agent.py,battery-warn} "$D/local/bin/"
rm -rf "$D/shell-overlay"
cd "$S"
find . -type f ! -name '*.bak*' ! -name '*.orig' ! -path '*__pycache__*' | while read -r f; do
    if [ ! -e "$U/$f" ] || ! cmp -s "$f" "$U/$f"; then
        mkdir -p "$D/shell-overlay/$(dirname "$f")"; cp -p "$f" "$D/shell-overlay/$f"
    fi
done
echo "Синхронизировано в $D"
