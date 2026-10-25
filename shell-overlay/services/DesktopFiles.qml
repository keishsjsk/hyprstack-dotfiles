pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Hyprstack.Config
import qs.utils

// Files on the desktop (XDG_DESKTOP_DIR) shown as icons in stacking mode.
Singleton {
    id: root

    readonly property string helper: Paths.toLocalFile(Qt.resolvedUrl("../assets/desktop_helper.py"))
    property string dir
    property list<var> entries: []

    // "free": icons stay where they were dropped, "grid": auto-arranged by name
    property string mode: "free"
    property var positions: ({})
    property list<string> selected: []

    // Context menu / dialog shown by DesktopPopup
    property bool menuOpen
    property real menuX
    property real menuY
    property list<var> menuItems: []
    property string dialog // "", "rename", "mkdir", "pick"
    property var dialogTarget
    property ShellScreen screen: Quickshell.screens[0] ?? null

    function isSelected(name: string): bool {
        return selected.includes(name);
    }

    function select(name: string, add: bool): void {
        if (!add)
            selected = [name];
        else if (isSelected(name))
            selected = selected.filter(n => n !== name);
        else
            selected = [...selected, name];
    }

    function selectedEntries(): list<var> {
        return entries.filter(e => selected.includes(e.name));
    }

    function activate(entry: var): void {
        if (entry.desktop)
            Quickshell.execDetached(["python3", helper, "launch", entry.path]);
        else
            Quickshell.execDetached(["xdg-open", entry.path]);
    }

    function showInFileManager(entry: var): void {
        Quickshell.execDetached(["dolphin", "--select", entry.path]);
    }

    function openDir(): void {
        Quickshell.execDetached(["xdg-open", dir]);
    }

    function openTerminal(): void {
        Quickshell.execDetached({
            command: GlobalConfig.general.apps.terminal,
            workingDirectory: dir
        });
    }

    function copyPaths(list: list<var>): void {
        Quickshell.execDetached(["wl-copy", list.map(e => e.path).join("\n")]);
    }

    function trash(list: list<var>): void {
        if (list.length)
            Quickshell.execDetached(["gio", "trash", ...list.map(e => e.path)]);
        selected = [];
    }

    function rename(entry: var, name: string): void {
        if (!name || name === entry.name)
            return;
        const pos = positions[entry.name];
        if (pos) {
            const next = Object.assign({}, positions);
            delete next[entry.name];
            next[name] = pos;
            setPositions(next);
        }
        run(["rename", entry.path, name], "Не удалось переименовать", "");
    }

    function makeDir(name: string): void {
        run(["mkdir", dir, name || "Новая папка"], "Не удалось создать папку", "");
    }

    function pin(appId: string, notify: bool): void {
        run(["pin", appId, dir], "Не удалось добавить ярлык", notify ? "Ярлык добавлен на рабочий стол" : "");
    }

    function run(args: list<string>, error: string, done: string): void {
        const proc = actionProc.createObject(root, {
            command: ["python3", helper, ...args],
            error,
            done: done ?? ""
        });
        proc.running = true;
    }

    function setMode(m: string): void {
        mode = m;
        save();
    }

    function setPositions(p: var): void {
        positions = p;
        save();
    }

    function save(): void {
        storage.setText(JSON.stringify({
            mode,
            positions
        }, null, 2));
    }

    function openMenu(x: real, y: real, items: list<var>): void {
        menuX = x;
        menuY = y;
        menuItems = items;
        menuOpen = true;
    }

    function openDialog(kind: string, target: var): void {
        menuOpen = false;
        dialogTarget = target ?? null;
        dialog = kind;
    }

    function closePopup(): void {
        menuOpen = false;
        dialog = "";
    }

    Component {
        id: actionProc

        Process {
            id: proc

            property string error
            property string done

            stderr: StdioCollector {
                id: err
            }
            onExited: code => {
                if (code !== 0)
                    Quickshell.execDetached(["notify-send", "-a", "hyprstack-shell", "-u", "low", proc.error, err.text.trim()]);
                else if (proc.done)
                    Quickshell.execDetached(["notify-send", "-a", "hyprstack-shell", "-u", "low", proc.done]);
                proc.destroy();
            }
        }
    }

    FileView {
        id: storage

        path: `${Paths.state}/desktop-icons.json`
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.mode = data.mode === "grid" ? "grid" : "free";
                root.positions = data.positions ?? {};
            } catch (error) {
                console.warn(`Unable to load desktop icon positions: ${error}`);
            }
        }
    }

    Process {
        running: true
        command: ["xdg-user-dir", "DESKTOP"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.dir = text.trim() || `${Paths.home}/Desktop`;
                watcher.running = true;
            }
        }
    }

    Process {
        id: watcher

        command: ["python3", root.helper, "watch", root.dir]
        onExited: restartWatcher.start()
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    root.entries = JSON.parse(data);
                    root.selected = root.selected.filter(n => root.entries.some(e => e.name === n));
                } catch (error) {
                    console.warn(`Bad desktop listing: ${error}`);
                }
            }
        }
    }

    Timer {
        id: restartWatcher

        interval: 3000
        onTriggered: watcher.running = true
    }
}
