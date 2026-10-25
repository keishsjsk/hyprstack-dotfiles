#!/usr/bin/env bash
# Установка Hyprland + hyprstack с настройками keish.
#   bash <(curl -fsSL https://raw.githubusercontent.com/keishsjsk/hyprstack-dotfiles/main/install.sh)
# Переменные:
#   SKIP_DEPS=1    не ставить пакеты через pacman
#   SKIP_BUILD=1   не собирать hyprstack (если уже установлен)
#   MONITORS=keish взять мои мониторы (ноутбук 2560x1440 + XT27N1)
set -euo pipefail

REPO_URL="https://github.com/keishsjsk/hyprstack-dotfiles.git"
UPSTREAM_URL="https://github.com/hase9awa/hyprstack-shell.git"
UPSTREAM_REV="8e39fad"   # версия hyprstack, на которую рассчитаны правки

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "запускай без sudo"
command -v pacman >/dev/null || die "нужен Arch / CachyOS (pacman)"

config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
data_dir=${XDG_DATA_HOME:-$HOME/.local/share}
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/keish-dotfiles

# --- 1. Пакеты -------------------------------------------------------------
if [ "${SKIP_DEPS:-0}" != 1 ]; then
    say "Ставлю пакеты (попросит пароль sudo)"
    sudo pacman -Syu --needed \
        base-devel git cmake ninja pkgconf gettext rsync curl \
        hyprland quickshell nlohmann-json qt6-base qt6-declarative qt6-shadertools \
        qt6-svg qt6-imageformats qt6-wayland qt5ct qt6ct libqalculate lm_sensors \
        pixman libdrm libinput systemd-libs wayland libxkbcommon pango cairo \
        python python-pillow python-dbus python-gobject kitty firefox fuzzel btop pavucontrol \
        wl-clipboard cliphist grim slurp wf-recorder swappy libnotify \
        brightnessctl networkmanager pipewire pipewire-pulse wireplumber \
        polkit hyprlock hyprpicker xdg-utils xdg-user-dirs libxml2 adwaita-icon-theme dbus \
        glib2 gsettings-desktop-schemas xdg-desktop-portal-gtk \
        papirus-icon-theme xorg-xrdb bluez bluez-utils upower power-profiles-daemon
fi

# --- 2. Репозиторий с настройками -----------------------------------------
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
if [ -n "$script_dir" ] && [ -d "$script_dir/shell-overlay" ]; then
    dots=$script_dir
else
    dots=$cache_dir/dotfiles
    say "Скачиваю настройки"
    if [ -d "$dots/.git" ]; then git -C "$dots" pull --ff-only; else
        mkdir -p "$cache_dir"; git clone --depth 1 "$REPO_URL" "$dots"; fi
fi

# --- 3. Сборка hyprstack ---------------------------------------------------
if [ "${SKIP_BUILD:-0}" != 1 ]; then
    src=$cache_dir/hyprstack-shell
    say "Собираю hyprstack ($UPSTREAM_REV)"
    [ -d "$src/.git" ] || git clone "$UPSTREAM_URL" "$src"
    git -C "$src" fetch --quiet origin
    git -C "$src" checkout --quiet "$UPSTREAM_REV"
    cmake -S "$src" -B "$src/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
        -DCMAKE_INSTALL_DATADIR="$data_dir"
    cmake --build "$src/build" --parallel "${JOBS:-2}"
    cmake --install "$src/build"
    mkdir -p "$config_dir/systemd/user"
    cp "$src/distribution/systemd/user/hyprstack-session.service" "$config_dir/systemd/user/"
fi
[ -d "$data_dir/hyprstack/shell" ] || die "hyprstack не установлен ($data_dir/hyprstack/shell)"

# --- 4. Резервная копия ----------------------------------------------------
backup=$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)
say "Старые настройки → $backup"
mkdir -p "$backup"
old_monitors=""
[ -f "$config_dir/hyprstack/monitors.lua" ] && old_monitors=$backup/hyprstack/monitors.lua
for name in hypr hyprstack quickshell uwsm fontconfig kitty; do
    [ -e "$config_dir/$name" ] && mv "$config_dir/$name" "$backup/"
done

# --- 5. Конфиги ------------------------------------------------------------
say "Копирую конфиги"
mkdir -p "$config_dir" "$config_dir/systemd/user" "$HOME/.local/bin"
cp -R "$dots/config/." "$config_dir/"
cp "$dots/local/bin/"* "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/bt-agent.py" "$HOME/.local/bin/battery-warn"
grep -rlI '/home/keish' "$config_dir"/{hypr,hyprstack,quickshell,uwsm,fontconfig,kitty} 2>/dev/null \
    | xargs -r sed -i "s|/home/keish|$HOME|g"

if [ "${MONITORS:-}" = keish ]; then
    cp "$dots/monitors.keish.lua" "$config_dir/hyprstack/monitors.lua"
elif [ -n "$old_monitors" ]; then
    cp "$old_monitors" "$config_dir/hyprstack/monitors.lua"
else
    printf -- '-- Свои мониторы. Пример: monitors.keish.lua в репозитории.\n' \
        > "$config_dir/hyprstack/monitors.lua"
fi

# --- 6. Правки оболочки ----------------------------------------------------
say "Накладываю правки на оболочку"
cp -R "$dots/shell-overlay/." "$data_dir/hyprstack/shell/"

# --- 7. Курсор, обои, шрифты -----------------------------------------------
mkdir -p "$data_dir/icons" "$HOME/.icons"
rsync -a "$dots/icons/" "$data_dir/icons/"
ln -sfn "$data_dir/icons/Volantes-Dark" "$HOME/.icons/Volantes-Dark"
pics=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
mkdir -p "$pics/Wallpapers"
cp "$dots/wallpapers/"* "$pics/Wallpapers/"
fc-cache -f >/dev/null 2>&1 || true

# --- 8. Службы -------------------------------------------------------------
say "Включаю службы"
systemctl --user daemon-reload || true
systemctl --user enable bt-agent.service battery-warn.service || true
sudo systemctl enable --now bluetooth.service power-profiles-daemon.service || true
export PATH="$HOME/.local/bin:$PATH"
# цвета берутся из обоев
hyprstack wallpaper -f "$pics/Wallpapers/wallpaper.jpg" >/dev/null 2>&1 || true
hyprstack scheme set -n dynamic -m dark -v tonalspot >/dev/null 2>&1 || true
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null || true
    systemctl --user restart hyprstack-session || true
fi

say "Готово! Резервная копия: $backup"
echo "Перезайди в Hyprland, потом: hyprstack-doctor; hyprctl configerrors"
echo "Обои: hyprstack wallpaper -f \"$pics/Wallpapers/wallpaper.jpg\""
