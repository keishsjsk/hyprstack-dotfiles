pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Hyprstack.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// Context menu and small dialogs for the desktop icons. Lives on the overlay
// layer so it stays above windows; any click outside closes it.
StyledWindow {
    id: root

    name: "desktop-popup"
    screen: DesktopFiles.screen
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: DesktopFiles.closePopup()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: DesktopFiles.closePopup()
    }

    Elevation {
        id: menu

        visible: DesktopFiles.menuOpen
        x: Math.max(8, Math.min(root.width - width - 8, DesktopFiles.menuX))
        y: Math.max(8, Math.min(root.height - height - 8, DesktopFiles.menuY))
        implicitWidth: Math.max(220 * Tokens.scale, column.implicitWidth + column.anchors.margins * 2)
        implicitHeight: column.implicitHeight + column.anchors.margins * 2
        radius: Tokens.rounding.large
        level: 2

        transformOrigin: Item.TopLeft
        onVisibleChanged: if (visible) menuAppear.restart()
        Component.onCompleted: if (visible) menuAppear.restart()

        ParallelAnimation {
            id: menuAppear

            NumberAnimation {
                target: menu
                property: "opacity"
                from: 0
                to: 1
                duration: 70
            }
            NumberAnimation {
                target: menu
                property: "scale"
                from: 0.94
                to: 1
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: Colours.palette.m3surfaceContainerLow

            ColumnLayout {
                id: column

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                spacing: 0

                Repeater {
                    model: DesktopFiles.menuItems

                    Item {
                        id: opt

                        required property var modelData
                        readonly property bool separator: !!modelData.separator
                        readonly property color fg: modelData.danger ? Colours.palette.m3error : Colours.palette.m3onSurface

                        Layout.fillWidth: true
                        implicitWidth: separator ? 0 : row.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: separator ? Tokens.spacing.small * 2 + 1 : row.implicitHeight + Tokens.padding.medium * 2

                        Rectangle {
                            visible: opt.separator
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            height: 1
                            color: Colours.palette.m3outlineVariant
                        }

                        StateLayer {
                            visible: !opt.separator
                            disabled: opt.separator
                            radius: Tokens.rounding.medium
                            color: opt.fg
                            onClicked: {
                                const action = opt.modelData.action;
                                DesktopFiles.menuOpen = false;
                                action?.();
                            }
                        }

                        RowLayout {
                            id: row

                            visible: !opt.separator
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: opt.modelData.icon ?? ""
                                color: opt.modelData.danger ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: opt.modelData.text ?? ""
                                color: opt.fg
                            }
                        }
                    }
                }
            }
        }
    }

    // Rename / new folder / app picker
    Elevation {
        id: dialog

        readonly property string kind: DesktopFiles.dialog
        readonly property bool picking: kind === "pick"
        readonly property var apps: {
            const q = field.text.trim();
            if (!picking)
                return [];
            const all = [...DesktopEntries.applications.values].filter(a => !a.noDisplay);
            const ql = q.toLowerCase();
            const hits = q ? all.filter(a => `${a.name} ${a.genericName} ${a.keywords.join(" ")}`.toLowerCase().includes(ql)) : all;
            return hits.sort((a, b) => (q ? a.name.toLowerCase().startsWith(ql) ? 0 : 1 : 0) - (q ? b.name.toLowerCase().startsWith(ql) ? 0 : 1 : 0) || a.name.localeCompare(b.name));
        }

        function accept(): void {
            const text = field.text.trim();
            if (kind === "rename")
                DesktopFiles.rename(DesktopFiles.dialogTarget, text);
            else if (kind === "mkdir")
                DesktopFiles.makeDir(text);
            else if (picking && apps.length)
                DesktopFiles.pin(apps[Math.max(0, list.currentIndex)].id, false);
            DesktopFiles.closePopup();
        }

        visible: kind.length > 0
        anchors.centerIn: parent
        implicitWidth: 420 * Tokens.scale
        implicitHeight: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        level: 3

        transformOrigin: Item.Center
        Component.onCompleted: if (visible) dialogAppear.restart()

        ParallelAnimation {
            id: dialogAppear

            NumberAnimation {
                target: dialog
                property: "opacity"
                from: 0
                to: 1
                duration: 70
            }
            NumberAnimation {
                target: dialog
                property: "scale"
                from: 0.94
                to: 1
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        onVisibleChanged: if (visible) {
            dialogAppear.restart();
            field.text = kind === "rename" ? DesktopFiles.dialogTarget?.name ?? "" : kind === "mkdir" ? "Новая папка" : "";
            Qt.callLater(() => {
                field.forceActiveFocus();
                if (kind === "rename") {
                    const dot = field.text.lastIndexOf(".");
                    field.select(0, DesktopFiles.dialogTarget?.dir || dot <= 0 ? field.text.length : dot);
                } else {
                    field.selectAll();
                }
            });
        }

        MouseArea {
            anchors.fill: parent
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    text: dialog.kind === "rename" ? "Переименовать" : dialog.kind === "mkdir" ? "Новая папка" : "Добавить ярлык приложения"
                    font: Tokens.font.title.medium
                }

                StyledTextField {
                    id: field

                    Layout.fillWidth: true
                    leadingIcon: dialog.picking ? "search" : dialog.kind === "mkdir" ? "create_new_folder" : "edit"
                    placeholderText: dialog.picking ? "Поиск приложения" : "Имя"
                    onTextChanged: list.currentIndex = 0
                    Keys.onReturnPressed: dialog.accept()
                    Keys.onEnterPressed: dialog.accept()
                    Keys.onEscapePressed: DesktopFiles.closePopup()
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                }

                StyledListView {
                    id: list

                    visible: dialog.picking
                    Layout.fillWidth: true
                    Layout.preferredHeight: dialog.picking ? 360 * Tokens.scale : 0
                    clip: true
                    model: dialog.apps
                    highlightMoveDuration: 0

                    delegate: Item {
                        id: app

                        required property var modelData
                        required property int index

                        width: list.width
                        implicitHeight: 48 * Tokens.scale

                        StyledRect {
                            anchors.fill: parent
                            radius: Tokens.rounding.medium
                            color: app.index === list.currentIndex ? Colours.palette.m3secondaryContainer : "transparent"
                        }

                        StateLayer {
                            radius: Tokens.rounding.medium
                            onClicked: {
                                list.currentIndex = app.index;
                                dialog.accept();
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            IconImage {
                                asynchronous: true
                                implicitSize: 32 * Tokens.scale
                                source: Quickshell.iconPath(app.modelData?.icon, "image-missing")
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: app.modelData?.name ?? ""
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: "Отмена"
                        type: TextButton.Tonal
                        onClicked: DesktopFiles.closePopup()
                    }

                    TextButton {
                        text: dialog.picking ? "Добавить" : "OK"
                        type: TextButton.Filled
                        disabled: dialog.picking ? dialog.apps.length === 0 : field.text.trim().length === 0
                        onClicked: dialog.accept()
                    }
                }
            }
        }
    }
}
