pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness
    required property bool atBottom
    // Отступ от краёв экрана, как у панелек (иначе меню прилипает к краю).
    property real edgeMargin
    // Допустимые границы меню (левый/правый край), например ровная часть панельки.
    property real minX: -Infinity
    property real maxX: Infinity

    readonly property alias content: content
    readonly property bool hovered: hover.hovered
    property real offsetScale: content.isDetached || content.hasCurrent ? 0 : 1

    visible: width > 0 && height > 0
    clip: true

    HoverHandler { id: hover }

    implicitWidth: content.implicitWidth
    implicitHeight: Math.max(0, content.implicitHeight * (1 - offsetScale))

    x: {
        if (content.isDetached)
            return (parent.width - width) / 2;
        const w = content.nonAnimWidth;
        const lo = Math.max(edgeMargin, minX), hi = Math.min(parent.width - w - edgeMargin, maxX - w);
        if (lo > hi)
            return (lo + hi) / 2;
        return Math.max(lo, Math.min(content.currentCenter - borderThickness - w / 2, hi));
    }
    y: content.isDetached ? (parent.height - height) / 2 : atBottom ? parent.height - height : 0

    Behavior on offsetScale {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Behavior on x {
        enabled: root.offsetScale === 0 && !content.isDetached
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.atBottom ? root.height - height + (height + 5) * root.offsetScale
            : (-height - 5) * root.offsetScale
    }
}
