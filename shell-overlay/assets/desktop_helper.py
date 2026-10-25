#!/usr/bin/env python3
"""Desktop icons helper for the hyprstack shell.

watch DIR            print the directory listing as one JSON line, again on every change
launch PATH          run a .desktop file
pin APP_ID DIR       copy an installed application's .desktop file into DIR
mkdir DIR NAME       create a folder (a free name is picked on collision)
rename PATH NAME     rename a file inside its directory
"""

import json
import os
import shutil
import sys
import warnings

warnings.filterwarnings("ignore")

import gi  # noqa: E402

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

try:
    gi.require_version("GioUnix", "2.0")
    from gi.repository import GioUnix

    DesktopAppInfo = GioUnix.DesktopAppInfo
except (ImportError, ValueError):
    DesktopAppInfo = Gio.DesktopAppInfo

ATTRS = "standard::name,standard::display-name,standard::type,standard::icon,standard::content-type,standard::is-hidden"


def icon_names(icon):
    if isinstance(icon, Gio.ThemedIcon):
        return [n for n in icon.get_names() if not n.endswith("-symbolic")]
    if isinstance(icon, Gio.FileIcon):
        return [icon.get_file().get_path()]
    return []


def describe(directory, info):
    name = info.get_name()
    path = os.path.join(directory, name)
    ctype = info.get_content_type() or ""
    is_dir = info.get_file_type() == Gio.FileType.DIRECTORY
    entry = {
        "name": name,
        "path": path,
        "label": info.get_display_name(),
        "dir": is_dir,
        "desktop": False,
        "image": ctype.startswith("image/"),
        "icons": icon_names(info.get_icon()),
    }
    if name.endswith(".desktop") and not is_dir:
        try:
            app = DesktopAppInfo.new_from_filename(path)
        except TypeError:
            app = None
        if app:
            entry["desktop"] = True
            entry["label"] = app.get_display_name() or entry["label"]
            app_icon = app.get_icon()
            if app_icon:
                entry["icons"] = icon_names(app_icon) + ["application-x-executable"]
    return entry


def listing(directory):
    entries = []
    try:
        enum = Gio.File.new_for_path(directory).enumerate_children(ATTRS, Gio.FileQueryInfoFlags.NONE, None)
    except GLib.Error:
        return entries
    for info in enum:
        if info.get_is_hidden() or info.get_name().startswith("."):
            continue
        entries.append(describe(directory, info))
    entries.sort(key=lambda e: (not e["dir"], e["label"].casefold()))
    return entries


def watch(directory):
    os.makedirs(directory, exist_ok=True)
    loop = GLib.MainLoop()
    pending = [0]

    def emit():
        pending[0] = 0
        print(json.dumps(listing(directory), ensure_ascii=False), flush=True)
        return False

    def changed(*_):
        if not pending[0]:
            pending[0] = GLib.timeout_add(150, emit)

    monitor = Gio.File.new_for_path(directory).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
    monitor.connect("changed", changed)
    emit()
    loop.run()


def free_path(directory, name):
    path = os.path.join(directory, name)
    if not os.path.lexists(path):
        return path
    stem, ext = os.path.splitext(name)
    if os.path.isdir(path) or not ext:
        stem, ext = name, ""
    i = 2
    while os.path.lexists(os.path.join(directory, f"{stem} ({i}){ext}")):
        i += 1
    return os.path.join(directory, f"{stem} ({i}){ext}")


def launch(path):
    app = DesktopAppInfo.new_from_filename(path)
    if not app:
        sys.exit(f"not a valid .desktop file: {path}")
    app.launch([], None)


def pin(app_id, directory):
    app = DesktopAppInfo.new(app_id if app_id.endswith(".desktop") else app_id + ".desktop")
    if not app or not app.get_filename():
        sys.exit(f"application not found: {app_id}")
    os.makedirs(directory, exist_ok=True)
    src = app.get_filename()
    dst = free_path(directory, os.path.basename(src))
    shutil.copyfile(src, dst)
    os.chmod(dst, 0o755)
    print(dst)


def make_dir(directory, name):
    path = free_path(directory, name)
    os.mkdir(path)
    print(path)


def rename(path, name):
    name = name.strip()
    if not name or "/" in name or name in (".", ".."):
        sys.exit("invalid name")
    dst = os.path.join(os.path.dirname(path), name)
    if os.path.lexists(dst):
        sys.exit(f"already exists: {name}")
    os.rename(path, dst)
    print(dst)


def main(argv):
    cmds = {"watch": (watch, 1), "launch": (launch, 1), "pin": (pin, 2), "mkdir": (make_dir, 2), "rename": (rename, 2)}
    if len(argv) < 2 or argv[1] not in cmds or len(argv) - 2 != cmds[argv[1]][1]:
        sys.exit(__doc__)
    fn, _ = cmds[argv[1]]
    fn(*argv[2:])


if __name__ == "__main__":
    main(sys.argv)
