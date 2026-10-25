pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Hyprstack.Config
import qs.components
import qs.services

// Плавающие панельки сверху: точки рабочих столов слева, окна стола по центру
// (скроллинг-режим), трей/часы/статус/питание справа.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property real islandHeight
    // Ширина панели уведомлений: правая панелька не уже её, чтобы края совпадали.
    property real minRightWidth

    readonly property real inset: 4 * Tokens.scale
    // Режим стопки: точки и статус сведены в одну панельку по центру.
    readonly property bool merged: Hypr.stacking
    readonly property real mergedGap: Tokens.spacing.large
    // Насколько правая панелька заходит на левую: оба внутренних поля минус промежуток.
    readonly property real mergedOverlap: wsIsland.height / 2 + (rightIsland.height - row.implicitHeight) / 2 - mergedGap
    readonly property real mergedWidth: wsIsland.width + rightIsland.width - mergedOverlap
    // Общая подложка слитой панельки (одна фигура — без наплыва блобов на стыке).
    readonly property alias mergedIsland: mergedIsland
    // Фон панелек рисуется блобами в ContentWindow, чтобы панели сливались с ними.
    readonly property alias wsIsland: wsIsland
    readonly property alias rightIsland: rightIsland
    readonly property alias centerIsland: centerIsland
    readonly property int dotCount: 5
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property int wsBase: Hypr.workspaceBase(monitor)
    readonly property int activeNumber: (monitor?.activeWorkspace?.id ?? 1) - wsBase

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;
        for (let i = 0; i < repeater.count; i++) {
            const tray = repeater.itemAt(i)?.item as Tray;
            if (tray)
                tray.expanded = false;
        }
    }

    function contains(x: real, y: real): bool {
        return visible && y >= 0 && y < height
            && ((x >= wsIsland.x && x < wsIsland.x + wsIsland.width)
                || (x >= rightIsland.x && x < rightIsland.x + rightIsland.width)
                || (centerIsland.visible && x >= centerIsland.x && x < centerIsland.x + centerIsland.width));
    }

    function entryAt(x: real): Item {
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            const position = item.mapToItem(root, 0, 0);
            if (x >= position.x && x < position.x + item.width)
                return item;
        }
        return null;
    }

    function checkPopout(x: real): void {
        const ch = entryAt(x);
        if (ch?.entryId !== "tray")
            closeTray();
        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const y = height / 2;
        if (ch.entryId === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const icon = items.childAt(mapToItem(items, x, y).x, items.height / 2);
            if (icon) {
                popouts.fromTop = true;
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => icon.mapToItem(root, icon.width / 2, 0).x);
                popouts.hasCurrent = true;
            } else {
                popouts.hasCurrent = false;
            }
        } else if (ch.entryId === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            if (!Config.bar.tray.compact || (tray.expanded && !tray.expandIcon.contains(mapToItem(tray.expandIcon, x, y)))) {
                const item = tray.layout.childAt(mapToItem(tray.layout, x, y).x, tray.layout.height / 2);
                for (let i = 0; i < tray.items.count; i++) {
                    const trayItem = tray.items.itemAt(i);
                    if (trayItem !== item)
                        continue;
                    popouts.fromTop = true;
                    popouts.currentName = `traymenu${i}`;
                    popouts.currentCenter = Qt.binding(() => trayItem.mapToItem(root, trayItem.width / 2, 0).x);
                    popouts.hasCurrent = true;
                    return;
                }
                popouts.hasCurrent = false;
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else {
            popouts.hasCurrent = false;
        }
    }

    function handleWheel(x: real, angleDelta: point): void {
        if (x >= wsIsland.x && x < wsIsland.x + wsIsland.width && angleDelta.y !== 0)
            Hypr.stepWorkspace(angleDelta.y > 0 ? -1 : 1, monitor);
    }

    height: islandHeight

    Item {
        id: mergedIsland

        x: wsIsland.x
        y: wsIsland.y
        width: root.mergedWidth
        height: wsIsland.height
    }

    StyledRect {
        id: wsIsland

        x: root.merged ? Math.round((root.width - root.mergedWidth) / 2) : root.inset * 2
        y: root.inset
        height: root.height - root.inset * 2
        width: dots.implicitWidth + height
        radius: Tokens.rounding.full
        color: "transparent"

        Row {
            id: dots

            anchors.centerIn: parent
            spacing: 7 * Tokens.scale

            Repeater {
                model: root.dotCount

                Item {
                    id: dot

                    required property int index
                    readonly property int number: index + 1
                    readonly property bool active: root.activeNumber === number

                    width: 18 * Tokens.scale
                    height: wsIsland.height

                    StyledRect {
                        anchors.centerIn: parent
                        width: dot.active ? parent.width : 9 * Tokens.scale
                        height: width
                        radius: Tokens.rounding.full
                        color: dot.active ? Colours.palette.m3primary
                            : Qt.alpha(Colours.palette.m3onSurface, dotArea.containsMouse ? 0.6 : 0.3)

                        Behavior on width { Anim {} }
                    }

                    MouseArea {
                        id: dotArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hypr.focusWorkspace(root.wsBase + dot.number, root.monitor)
                    }
                }
            }
        }
    }

    StyledRect {
        id: centerIsland

        visible: !Hypr.stacking && scrollTasks.windows.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.inset
        height: root.height - root.inset * 2
        width: scrollTasks.implicitWidth + height - scrollTasks.buttonSize
        radius: Tokens.rounding.full
        color: "transparent"

        ScrollTasks {
            id: scrollTasks

            anchors.centerIn: parent
            height: parent.height - 4 * Tokens.scale
            screen: root.screen
            radius: Tokens.rounding.full
            color: "transparent"
        }
    }

    StyledRect {
        id: rightIsland

        // Слитно: внутренние поля обеих панелек заменяются одним промежутком mergedGap.
        x: root.merged ? wsIsland.x + wsIsland.width - root.mergedOverlap
            : root.width - width - root.inset * 2
        y: root.inset
        height: root.height - root.inset * 2
        // Слитно справа поле как у точек слева, а не впритык к кнопке питания.
        readonly property real padLeft: (height - row.implicitHeight) / 2
        readonly property real padRight: root.merged ? height / 2 : padLeft
        width: Math.max(root.merged ? 0 : root.minRightWidth, row.implicitWidth + padLeft + padRight)
        radius: Tokens.rounding.full
        color: "transparent"

        RowLayout {
            id: row

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: (rightIsland.padLeft - rightIsland.padRight) / 2
            spacing: Tokens.spacing.medium

            Repeater {
                id: repeater

                model: ScriptModel {
                    values: {
                        const entries = root.Config.bar.entries.values.filter(e => e.enabled
                            && ["tray", "clock", "statusIcons", "power"].includes(e.id));
                        const power = entries.findIndex(e => e.id === "power");
                        if (root.Config.sidebar.enabled && root.Config.bar.showNotifications)
                            entries.splice(power < 0 ? entries.length : power, 0, {id: "notifications", enabled: true});
                        return entries;
                    }
                }

                DelegateChooser {
                    role: "id"

                    DelegateChoice {
                        roleValue: "tray"
                        delegate: Entry {
                            Tray {}
                        }
                    }
                    DelegateChoice {
                        roleValue: "clock"
                        delegate: Entry {
                            Clock {
                                screenState: root.screenState
                            }
                        }
                    }
                    DelegateChoice {
                        roleValue: "statusIcons"
                        delegate: Entry {
                            StatusIcons {}
                        }
                    }
                    DelegateChoice {
                        roleValue: "notifications"
                        delegate: Entry {
                            NotificationCenterButton {
                                screenState: root.screenState
                            }
                        }
                    }
                    DelegateChoice {
                        roleValue: "power"
                        delegate: Entry {
                            Power {
                                screenState: root.screenState
                            }
                        }
                    }
                }
            }
        }
    }

    component Entry: Item {
        required property var modelData
        default property Item item
        readonly property string entryId: modelData.id

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0
        children: item
    }
}
