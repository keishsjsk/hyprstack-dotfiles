pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Hyprstack.Config
import qs.components
import qs.services
import qs.utils

// Иконки окон активного рабочего стола в порядке колонок скроллинг-режима
StyledRect {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property int wsId: monitor?.activeWorkspace?.id ?? -1
    readonly property real iconSize: 20 * Tokens.scale * (Tokens.scale < 1 ? 1.2 : 1)
    readonly property real buttonSize: Math.max(iconSize, height - 6 * Tokens.scale)

    // Порядок колонок = порядок окон слева направо на ленте скроллинга
    readonly property list<HyprlandToplevel> windows: {
        const pos = t => t.lastIpcObject?.at ?? [0, 0];
        return Hypr.toplevelsForWs(wsId, GlobalConfig.bar.workspaces.ignoredTags).sort((a, b) => {
            const pa = pos(a), pb = pos(b);
            return pa[0] - pb[0] || pa[1] - pb[1];
        });
    }

    // Перестановка колонок не всегда шлёт событие окна, поэтому
    // перечитываем координаты, когда hyprstack обновляет состояние раскладки
    Connections {
        target: Hypr
        function onWindowStatesChanged(): void {
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 50
        onTriggered: Hyprland.refreshToplevels()
    }

    implicitWidth: row.implicitWidth + 6 * Tokens.scale
    radius: Tokens.rounding.full
    color: Colours.tPalette.m3surfaceContainer

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2 * Tokens.scale

        Repeater {
            model: root.windows

            StyledRect {
                id: button

                required property HyprlandToplevel modelData
                readonly property bool active: modelData === Hypr.activeToplevel

                implicitWidth: root.buttonSize
                implicitHeight: root.buttonSize
                radius: Tokens.rounding.full
                color: active ? Colours.palette.m3secondaryContainer : "transparent"

                Behavior on color {
                    CAnim {}
                }

                StateLayer {
                    radius: parent.radius
                    // windowAction("activate") работает только в стековом режиме,
                    // поэтому фокусируем окно напрямую, временно отключив перенос курсора
                    onClicked: Quickshell.execDetached(["hyprctl", "eval",
                        `local w = hl.get_config("cursor.no_warps"); hl.config({ cursor = { no_warps = true } }); `
                        + `hl.dispatch(hl.dsp.focus({ window = "address:${button.modelData.lastIpcObject.address}" })); `
                        + `hl.config({ cursor = { no_warps = w } })`])
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: root.iconSize
                    source: Icons.getAppIcon(button.modelData.lastIpcObject?.class ?? "", "application-x-executable")
                    asynchronous: true
                }
            }
        }
    }
}
