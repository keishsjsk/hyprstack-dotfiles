pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Hyprstack.Config
import qs.components
import qs.services
import qs.utils

// Desktop folder icons for stacking mode. Free mode keeps dropped positions,
// grid mode lays everything out by name.
Item {
    id: root

    readonly property real cellW: 92 * Tokens.scale
    readonly property real cellH: 104 * Tokens.scale
    readonly property real marginLeft: 20 * Tokens.scale
    readonly property real marginTop: 72 * Tokens.scale
    readonly property real marginBottom: 100 * Tokens.scale
    readonly property int rows: Math.max(1, Math.floor((height - marginTop - marginBottom) / cellH))
    readonly property int cols: Math.max(1, Math.floor((width - marginLeft * 2) / cellW))
    readonly property bool free: DesktopFiles.mode === "free"
    // Areas taken by ~/.config/quickshell/desktop-widgets; cells under them stay empty
    property var reserved: []
    readonly property var blocked: computeBlocked(reserved, rows, cols, cellW, cellH, marginLeft, marginTop)
    readonly property var layout: computeLayout(DesktopFiles.entries, DesktopFiles.positions, free, rows, cols, blocked)

    property bool dragging
    property real dragDx
    property real dragDy
    property rect band
    property bool banding

    function key(col: int, row: int): int {
        return col * 10000 + row;
    }

    function computeBlocked(reserved: var, rows: int, cols: int, cw: real, ch: real, mx: real, my: real): var {
        const res = new Set();
        const pad = 4;
        for (const r of reserved) {
            for (let c = 0; c < cols; c++) {
                for (let w = 0; w < rows; w++) {
                    const x = mx + c * cw, y = my + w * ch;
                    if (x + pad < r.x + r.w && x + cw - pad > r.x && y + pad < r.y + r.h && y + ch - pad > r.y)
                        res.add(key(c, w));
                }
            }
        }
        return res;
    }

    function computeLayout(entries: var, positions: var, free: bool, rows: int, cols: int, blocked: var): var {
        const res = {};
        const used = new Set(blocked);
        if (free) {
            for (const e of entries) {
                const p = positions[e.name];
                if (p && p.col < cols && p.row < rows && !used.has(key(p.col, p.row))) {
                    res[e.name] = { col: p.col, row: p.row };
                    used.add(key(p.col, p.row));
                }
            }
        }
        let i = 0;
        for (const e of entries) {
            if (res[e.name])
                continue;
            while (i < rows * cols && used.has(key(Math.floor(i / rows), i % rows)))
                i++;
            res[e.name] = { col: Math.floor(i / rows), row: i % rows };
            used.add(key(res[e.name].col, res[e.name].row));
        }
        return res;
    }

    // Remember auto-placed icons in free mode so later additions don't shuffle them.
    // Stored spots are kept even while a widget covers them, so icons return when it shrinks.
    onLayoutChanged: Qt.callLater(() => {
        if (!free || !DesktopFiles.entries.length)
            return;
        const stored = DesktopFiles.positions;
        const names = DesktopFiles.entries.map(e => e.name);
        if (names.length === Object.keys(stored).length && names.every(n => stored[n]))
            return;
        const next = {};
        for (const n of names)
            next[n] = stored[n] ?? layout[n];
        DesktopFiles.setPositions(next);
    })

    function cellX(col: int): real {
        return marginLeft + col * cellW;
    }

    function cellY(row: int): real {
        return marginTop + row * cellH;
    }

    function drop(): void {
        const moving = DesktopFiles.selected;
        const dc = Math.round(dragDx / cellW);
        const dr = Math.round(dragDy / cellH);
        const next = {};
        const used = new Set(blocked);
        for (const e of DesktopFiles.entries) {
            if (moving.includes(e.name))
                continue;
            next[e.name] = DesktopFiles.positions[e.name] ?? layout[e.name];
            used.add(key(layout[e.name].col, layout[e.name].row));
        }
        const order = moving.filter(n => layout[n]).sort((a, b) => key(layout[a].col, layout[a].row) - key(layout[b].col, layout[b].row));
        for (const name of order) {
            const tc = Math.max(0, Math.min(cols - 1, layout[name].col + dc));
            const tr = Math.max(0, Math.min(rows - 1, layout[name].row + dr));
            let best = null;
            let bestDist = Infinity;
            for (let c = 0; c < cols; c++) {
                for (let r = 0; r < rows; r++) {
                    const d = (c - tc) ** 2 + (r - tr) ** 2;
                    if (d < bestDist && !used.has(key(c, r))) {
                        best = { col: c, row: r };
                        bestDist = d;
                    }
                }
            }
            if (!best)
                best = layout[name];
            next[name] = best;
            used.add(key(best.col, best.row));
        }
        DesktopFiles.setPositions(next);
    }

    function updateBand(x1: real, y1: real, x2: real, y2: real, add: var): void {
        band = Qt.rect(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
        const hit = DesktopFiles.entries.filter(e => {
            const p = layout[e.name];
            if (!p)
                return false;
            const x = cellX(p.col), y = cellY(p.row);
            return x < band.x + band.width && x + cellW > band.x && y < band.y + band.height && y + cellH > band.y;
        }).map(e => e.name);
        DesktopFiles.selected = [...new Set([...add, ...hit])];
    }

    function itemMenu(x: real, y: real): void {
        const sel = DesktopFiles.selectedEntries();
        if (!sel.length)
            return;
        const items = [];
        if (sel.length === 1) {
            const e = sel[0];
            items.push({ text: e.desktop ? "Запустить" : "Открыть", icon: e.desktop ? "play_arrow" : "open_in_new", action: () => DesktopFiles.activate(e) });
            if (!e.dir && !e.desktop)
                items.push({ text: "Показать в Dolphin", icon: "folder_open", action: () => DesktopFiles.showInFileManager(e) });
            items.push({ text: "Переименовать", icon: "edit", action: () => DesktopFiles.openDialog("rename", e) });
            items.push({ text: "Копировать путь", icon: "content_copy", action: () => DesktopFiles.copyPaths(sel) });
        } else {
            items.push({ text: `Открыть все (${sel.length})`, icon: "open_in_new", action: () => sel.forEach(e => DesktopFiles.activate(e)) });
            items.push({ text: "Копировать пути", icon: "content_copy", action: () => DesktopFiles.copyPaths(sel) });
        }
        items.push({ separator: true });
        // Shortcuts only remove the .desktop copy, the app itself stays installed
        const shortcuts = sel.every(e => e.desktop);
        const removeText = shortcuts ? (sel.length > 1 ? `Убрать ярлыки (${sel.length})` : "Убрать ярлык")
            : (sel.length > 1 ? `В корзину (${sel.length})` : "В корзину");
        items.push({ text: removeText, icon: shortcuts ? "link_off" : "delete", danger: true, action: () => DesktopFiles.trash(sel) });
        DesktopFiles.openMenu(x, y, items);
    }

    function desktopMenu(x: real, y: real): void {
        DesktopFiles.openMenu(x, y, [
            { text: "Создать папку", icon: "create_new_folder", action: () => DesktopFiles.openDialog("mkdir") },
            { text: "Добавить ярлык приложения", icon: "add_to_home_screen", action: () => DesktopFiles.openDialog("pick") },
            { separator: true },
            { text: "Свободная расстановка", icon: free ? "radio_button_checked" : "radio_button_unchecked", action: () => DesktopFiles.setMode("free") },
            { text: "Автоматическая сетка", icon: free ? "radio_button_unchecked" : "radio_button_checked", action: () => DesktopFiles.setMode("grid") },
            { text: "Упорядочить по имени", icon: "sort_by_alpha", action: () => DesktopFiles.setPositions({}) },
            { separator: true },
            { text: "Открыть папку рабочего стола", icon: "folder_open", action: () => DesktopFiles.openDir() },
            { text: "Открыть терминал здесь", icon: "terminal", action: () => DesktopFiles.openTerminal() }
        ]);
    }

    function iconSource(e: var): string {
        for (const n of e.icons) {
            if (n.startsWith("/"))
                return Paths.fileUrl(n);
            const p = Quickshell.iconPath(n, true);
            if (p)
                return p;
        }
        return Quickshell.iconPath(e.dir ? "folder" : "text-x-generic", "image-missing");
    }

    // Empty desktop area: rubber band selection and the desktop menu
    MouseArea {
        id: area

        property real startX
        property real startY
        property var startSel: []

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: e => {
            if (e.button === Qt.RightButton) {
                DesktopFiles.selected = [];
                root.desktopMenu(e.x, e.y);
                return;
            }
            startX = e.x;
            startY = e.y;
            startSel = e.modifiers & (Qt.ControlModifier | Qt.ShiftModifier) ? DesktopFiles.selected : [];
            DesktopFiles.selected = startSel;
        }
        onPositionChanged: e => {
            if (!(e.buttons & Qt.LeftButton))
                return;
            root.banding = true;
            root.updateBand(startX, startY, e.x, e.y, startSel);
        }
        onReleased: root.banding = false
    }

    Rectangle {
        visible: root.banding
        x: root.band.x
        y: root.band.y
        width: root.band.width
        height: root.band.height
        radius: Tokens.rounding.extraSmall
        color: Qt.alpha(Colours.palette.m3primary, 0.18)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.7)
    }

    Repeater {
        model: DesktopFiles.entries

        Item {
            id: icon

            required property var modelData
            readonly property var pos: root.layout[modelData.name] ?? { col: 0, row: 0 }
            readonly property bool selected: DesktopFiles.selected.includes(modelData.name)
            readonly property bool moving: root.dragging && selected

            x: root.cellX(pos.col) + (moving ? root.dragDx : 0)
            y: root.cellY(pos.row) + (moving ? root.dragDy : 0)
            z: moving ? 2 : 1
            width: root.cellW
            height: root.cellH
            opacity: moving ? 0.75 : 1

            Behavior on x {
                enabled: !root.dragging
                Anim {}
            }
            Behavior on y {
                enabled: !root.dragging
                Anim {}
            }

            StyledRect {
                anchors.fill: parent
                anchors.margins: 2 * Tokens.scale
                radius: Tokens.rounding.medium
                color: icon.selected ? Qt.alpha(Colours.palette.m3primary, 0.32)
                    : mouse.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : "transparent"
                border.width: icon.selected ? 1 : 0
                border.color: Qt.alpha(Colours.palette.m3primary, 0.6)

                Behavior on color {
                    CAnim {}
                }
            }

            Loader {
                id: image

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8 * Tokens.scale
                width: 52 * Tokens.scale
                height: 52 * Tokens.scale

                sourceComponent: icon.modelData.image ? thumb : themed
            }

            Component {
                id: themed

                IconImage {
                    asynchronous: true
                    implicitSize: 52 * Tokens.scale
                    source: root.iconSource(icon.modelData)
                }
            }

            Component {
                id: thumb

                Image {
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: 104 * Tokens.scale
                    sourceSize.height: 104 * Tokens.scale
                    source: Paths.fileUrl(icon.modelData.path)
                }
            }

            StyledText {
                id: label

                anchors.top: image.bottom
                anchors.topMargin: 4 * Tokens.scale
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 8 * Tokens.scale

                text: icon.modelData.label
                font: Tokens.font.body.small
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "black"
                    shadowOpacity: 0.9
                    shadowBlur: 0.4
                    shadowVerticalOffset: 1
                    shadowHorizontalOffset: 0
                }
            }

            MouseArea {
                id: mouse

                property point start
                property bool additive

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

                onPressed: e => {
                    const name = icon.modelData.name;
                    if (e.button === Qt.RightButton) {
                        if (!icon.selected)
                            DesktopFiles.select(name, false);
                        const p = mapToItem(root, e.x, e.y);
                        root.itemMenu(p.x, p.y);
                        return;
                    }
                    additive = !!(e.modifiers & Qt.ControlModifier);
                    if (additive)
                        DesktopFiles.select(name, true);
                    else if (!icon.selected)
                        DesktopFiles.select(name, false);
                    start = mapToItem(root, e.x, e.y);
                }
                onPositionChanged: e => {
                    if (!(e.buttons & Qt.LeftButton) || !root.free || !icon.selected)
                        return;
                    const p = mapToItem(root, e.x, e.y);
                    if (!root.dragging && Math.hypot(p.x - start.x, p.y - start.y) < 8 * Tokens.scale)
                        return;
                    root.dragging = true;
                    root.dragDx = p.x - start.x;
                    root.dragDy = p.y - start.y;
                }
                onReleased: e => {
                    if (e.button !== Qt.LeftButton)
                        return;
                    if (root.dragging) {
                        root.drop();
                        root.dragging = false;
                        root.dragDx = 0;
                        root.dragDy = 0;
                    } else if (!additive) {
                        DesktopFiles.select(icon.modelData.name, false);
                    }
                }
                onDoubleClicked: e => {
                    if (e.button === Qt.LeftButton)
                        DesktopFiles.activate(icon.modelData);
                }
            }
        }
    }

    FileView {
        path: `${Paths.state}/desktop-reserved-${DesktopFiles.screen?.name ?? ""}.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.reserved = JSON.parse(text());
            } catch (error) {
                root.reserved = [];
            }
        }
        onLoadFailed: root.reserved = []
    }

    LazyLoader {
        active: DesktopFiles.menuOpen || DesktopFiles.dialog.length > 0

        DesktopPopup {}
    }
}
