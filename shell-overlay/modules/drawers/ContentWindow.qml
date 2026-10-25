pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Hyprstack.Blobs
import Hyprstack.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: (Tiling.desktopFrame ? (contentItem.Config.border.thickness * contentItem.Tokens.scale) : 0) * (1 - fsTransitionProg) * (1 - Hypr.stackingProgress)
    readonly property real borderRounding: (Tiling.desktopFrame ? (contentItem.Config.border.rounding * contentItem.Tokens.scale) : 0) * (1 - fsTransitionProg) * (1 - Hypr.stackingProgress)
    readonly property real shadowOpacity: Effects.shadowOpacity * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : borderThickness
    readonly property real tileFrameRadius: !Hypr.stacking && !Tiling.gaps && Tiling.desktopFrame && !hasFullscreen
        ? (contentItem.Config.border.rounding * contentItem.Tokens.scale) : 0

    function syncTileFrame(): void {
        if (Hypr.usingLua && screen)
            Hypr.extras.message(`eval if hl.plugin.hyprbars and hl.plugin.hyprbars.tile_frame then hl.plugin.hyprbars.tile_frame(${JSON.stringify(screen.name)},${tileFrameRadius}) end`);
    }
    onTileFrameRadiusChanged: syncTileFrame()
    onScreenChanged: syncTileFrame()
    Component.onCompleted: syncTileFrame()

    Connections {
        target: Hypr
        function onConfigReloaded(): void { Qt.callLater(root.syncTileFrame); }
        function onUsingLuaChanged(): void { root.syncTileFrame(); }
    }

    property color surfaceColour: Colours.tPalette.m3surface

    readonly property int dragMaskPadding: {
        if (Hypr.stacking || !Tiling.desktopFrame)
            return 0;
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.toplevels.values.length > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: screenState.sidebar || screenState.launcher || screenState.session
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: hasFullscreen && !(contentItem.Config.general.showOverFullscreen && focusGrab.active)
        ? emptyRegion : regions

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {}
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    Region {
        id: emptyRegion

        x: panels.x + panels.notifications.x
        y: panels.y + panels.notifications.y
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: root.width - width
            y: panels.y + panels.osdWrapper.y
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + root.borderThickness
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled))
                return true;
            if ((Hypr.stacking || !conf.dashboard.showOnHover) && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.dashboard = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.surfaceColour.a

        BlobGroup {
            id: blobGroup

            color: root.surfaceColour
            smoothing: (root.contentItem.Config.border.smoothing * root.contentItem.Tokens.scale)
            shadowColor: Effects.uiShadowsEnabled
                ? Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity)) : "transparent"
            shadowSize: Effects.uiShadowsEnabled ? Effects.shadowSize * root.contentItem.Tokens.scale : 0
            shadowOffset: 2 * root.contentItem.Tokens.scale
        }

        BlobInvertedRect {
            id: frameBg

            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: root.borderRounding
            // Без рамки край вынесен за экран, чтобы панельки не прилипали к нему.
            property real offscreen: 40 * Math.max(Hypr.stackingProgress, Tiling.desktopFrame ? 0 : 1)
            borderLeft: root.borderThickness - offscreen - anchors.margins - root.sdfBorderOffset
            borderRight: root.borderThickness - offscreen - anchors.margins - root.sdfBorderOffset
            borderTop: bar.topInset - bar.topIslandsHeight - offscreen - anchors.margins - root.sdfBorderOffset
            borderBottom: bar.bottomInset * (1 - Hypr.stackingProgress) - offscreen - anchors.margins - root.sdfBorderOffset
        }

        // Оконный режим: панельки — часть блоб-группы, всплывающие панели вытекают из них.
        IslandBg {
            island: topIslands.merged ? topIslands.mergedIsland : topIslands.wsIsland
            shown: topIslands.visible
        }

        IslandBg {
            id: rightIslandBg

            island: topIslands.rightIsland
            shown: topIslands.visible && !topIslands.merged
            // Уведомления вытягиваются из самой панельки каплей: её подложка растёт вниз
            // до низа уведомлений (свой фон уведомлений скрыт), без стыка двух фигур.
            readonly property real islandBottom: pos.y + island.height
            readonly property real notifsExtend: panels.notifications.visible && !topIslands.merged
                ? Math.max(0, panels.y + panels.notifications.y + panels.notifications.height - islandBottom) : 0
            // Центр уведомлений — отдельная панель: подложка дотягивается до неё, нижние углы прямые.
            readonly property real sidebarProgress: topIslands.merged || !panels.sidebar.visible || panels.sidebar.height <= 0 ? 0
                : panels.drip ? Math.min(1, panels.sidebar.height / Math.max(1, island.height))
                : panels.sidebar.atBottom ? Math.min(1, Math.max(0, 1 - panels.sidebar.y / Math.max(1, island.height)))
                : Math.min(1, Math.max(0, 1 - panels.sidebar.offsetScale))
            readonly property real sidebarGap: Math.max(0, panels.y + panels.sidebar.y - islandBottom)
            extend: Math.max(notifsExtend, (sidebarGap + 2) * sidebarProgress)
            attachProgress: Math.max(Math.min(1, notifsExtend / Math.max(1, island.height)), sidebarProgress)
            squareBottom: sidebarProgress > 0
        }

        IslandBg {
            island: topIslands.centerIsland
            shown: topIslands.visible && topIslands.centerIsland.visible
        }

        IslandBg {
            island: bar.content.tasks
            shown: Hypr.stacking && bar.content.visible && bar.content.tasks.visible
        }

        PanelBg {
            id: dashBg
            objectName: "dashboardBackground"

            panel: panels.dashboard
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.x + panels.sessionWrapper.x + panels.session.x
            implicitWidth: panels.session.width
        }

        PanelBg {
            id: sidebarBg

            panel: panels.sidebar
            deformAmount: 0.03
            deformScale: panels.drip || Hypr.stacking ? 0 : (deformAmount * Config.appearance.deformScale) / 10000
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            exclude: panels.sidebar.offsetScale > 0.08 ? [rightIslandBg] : [utilsBg, rightIslandBg]
            bottomLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
            // Без рамки справа стык с быстрыми переключателями тоже прямой.
            bottomRightRadius: topIslands.visible && !Tiling.desktopFrame ? bottomLeftRadius : radius
            topLeftRadius: radius * (1 - rightIslandBg.sidebarProgress)
            topRightRadius: radius * (1 - rightIslandBg.sidebarProgress)
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.x + panels.osdWrapper.x + panels.osd.x
            implicitWidth: panels.osd.width
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
            exclude: [rightIslandBg]
            visible: (!topIslands.visible || topIslands.merged) && panel.visible && panel.width > 0 && panel.height > 0
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            deformScale: panels.drip || Hypr.stacking ? 0 : (deformAmount * Config.appearance.deformScale) / 10000
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
            topRightRadius: topIslands.visible && !Tiling.desktopFrame ? topLeftRadius : radius
        }

        PanelBg {
            id: popoutBg
            objectName: "popoutBackground"

            // Keep the animated popout background joined to the horizontal bar.
            // Сплошной полосы нет: подложка дотягивается только до своей панельки, а не до края экрана.
            property real extraDepth: panels.popouts.isDetached ? 0 : 6 * Tokens.scale

            panel: panels.popoutsWrapper
            deformAmount: panels.popouts.isDetached ? 0.05 : panels.popouts.hasCurrent ? 0.15 : 0.1
            // Из верхних панелек — без «желе»: растяжение вылезало за панельку к краю экрана.
            deformScale: Hypr.stacking || (topIslands.visible && panels.popouts.fromTop && !panels.popouts.isDetached)
                ? 0 : (deformAmount * Config.appearance.deformScale) / 10000
            x: panels.x + panels.popoutsWrapper.x + panels.popouts.x
            y: panels.y + panels.popoutsWrapper.y + panels.popouts.y - (panels.popoutsWrapper.atBottom ? 0 : extraDepth)
            implicitWidth: panels.popouts.width
            implicitHeight: panels.popouts.height + extraDepth

            Behavior on extraDepth {
                Anim {}
            }
        }
    }

    TilingEdgeHint {
        screen: root.screen
        win: root
        panels: panels
        bar: bar
        group: blobGroup
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        bar: bar
        topIslands: topIslands
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            borderThickness: root.borderThickness

            // Меню из верхней панельки выходит из её ровной части, не из скруглённых концов.
            popoutsWrapper.minX: islandSpan ? islandSpan.x : -Infinity
            popoutsWrapper.maxX: islandSpan ? islandSpan.y : Infinity
            readonly property point islandSpanRaw: {
                const island = topIslands.rightIsland;
                island.x; island.width; topIslands.width;
                const p = island.mapToItem(root.contentItem, 0, 0);
                const r = island.height / 2 + 4 * Tokens.scale;
                return Qt.point(p.x - panels.x + r, p.x - panels.x + island.width - r);
            }
            readonly property var islandSpan: topIslands.visible && popouts.fromTop && !popouts.isDetached ? islandSpanRaw : null

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: popoutBg.deformMatrix
            }
        }

        TopIslands {
            id: topIslands

            width: parent.width
            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts
            islandHeight: bar.topIslandsHeight
            minRightWidth: panels.notifications.implicitWidth
            visible: !root.hasFullscreen && islandHeight > 0
        }

        BarWrapper {
            id: bar

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts

            fullscreen: root.hasFullscreen
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    component IslandBg: BlobRect {
        required property Item island
        required property bool shown
        property real attachProgress
        property real extend
        property bool squareBottom
        readonly property real fullRadius: island.height / 2
        readonly property real panelRadius: Math.min(fullRadius, Tokens.rounding.extraLarge)
        readonly property real topRadius: fullRadius + (panelRadius - fullRadius) * attachProgress
        readonly property real bottomRadius: fullRadius + ((squareBottom ? 0 : panelRadius) - fullRadius) * attachProgress
        readonly property point pos: {
            island.x; island.y; island.width; bar.y; topIslands.y;
            return island.mapToItem(root.contentItem, 0, 0);
        }

        visible: shown && island.width > 0
        group: visible ? blobGroup : null
        x: pos.x
        y: pos.y
        implicitWidth: island.width
        implicitHeight: island.height + extend
        radius: fullRadius
        deformScale: 0
        topLeftRadius: topRadius
        topRightRadius: topRadius
        bottomLeftRadius: bottomRadius
        bottomRightRadius: bottomRadius
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15

        visible: panel.visible && panel.width > 0 && panel.height > 0
        group: visible ? blobGroup : null
        x: panels.x + panel.x
        y: panels.y + panel.y
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.extraLarge
        deformScale: Hypr.stacking ? 0 : (deformAmount * Config.appearance.deformScale) / 10000
    }
}
