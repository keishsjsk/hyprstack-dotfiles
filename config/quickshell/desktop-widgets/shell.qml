//@ pragma NativeTextRendering
// Виджеты рабочего стола: видны только на рабочем столе 1.
// Слева сверху: загрузка CPU и батарея. Справа сверху: часы, погода и плеер.
// Интерактив: клик по CPU/часам/погоде раскрывает подробности, профили питания на батарее,
// в плеере — перемотка по полосе, громкость колесом, клик по обложке поднимает окно плеера.
// Запуск: qs -c desktop-widgets
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

ShellRoot {
    id: shell

    // ===== Настройки =====
    readonly property int workspace: 1          // на каком по счёту рабочем столе монитора показывать
    readonly property int cardWidth: 230
    readonly property int radius: 6            // скругление углов (0 = острые)
    readonly property int gap: 6
    // Отступы как у панелек hyprstack: 6 от края экрана, 6 под верхними панельками (низ на 40)
    readonly property int edge: 6
    readonly property int top: 40 + edge
    readonly property real cardOpacity: 0.88
    readonly property string fontFamily: "Noto Sans"
    readonly property string iconFont: "MesloLGL Nerd Font Propo"
    readonly property var terminal: ["kitty", "-e"]

    // ===== Цвета из темы hyprstack =====
    property var c: ({
        surface: "#171412", container: "#211e1c", onSurface: "#eeeeee",
        variant: "#b2b1b0", outline: "#42403e", primary: "#d8b697",
        secondary: "#c5cea1", tertiary: "#97d8b5", error: "#ffb4ab"
    })

    // ===== Основной экран =====
    // Виджеты живут на внешнем мониторе, если он подключён, иначе на экране ноутбука
    readonly property var primaryScreen: Array.from(Quickshell.screens).find(s => !s.name.startsWith("eDP")) ?? Quickshell.screens[0] ?? null
    // hyprstack нумерует рабочие столы по мониторам: id = база монитора + номер
    property var monitorBases: ({})

    FileView {
        path: Quickshell.env("HOME") + "/.config/hyprstack/workspaces.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                shell.monitorBases = j.per_monitor ? (j.monitor_bases ?? {}) : {};
            } catch (e) {}
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/hyprstack/scheme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text()).colours;
                const h = k => "#" + s[k];
                shell.c = {
                    surface: h("surface"), container: h("surfaceContainer"),
                    onSurface: h("onSurface"), variant: h("onSurfaceVariant"),
                    outline: h("outlineVariant"), primary: h("primary"),
                    secondary: h("secondary"), tertiary: h("tertiary"),
                    error: s.error ? h("error") : "#ffb4ab"
                };
            } catch (e) {}
        }
    }

    // ===== CPU / память =====
    property real cpuUsage: 0
    property var cpuPrev: null
    property real memUsed: 0                    // доля
    property string memText: ""
    property string loadText: ""
    property string uptimeText: ""
    property var topProcs: []
    property bool cpuDetails: false             // раскрыта ли карточка CPU хоть на одном экране

    FileView {
        id: procStat
        path: "/proc/stat"
        onLoaded: {
            const v = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = v[3] + (v[4] || 0);
            const total = v.reduce((a, b) => a + b, 0);
            if (shell.cpuPrev) {
                const dt = total - shell.cpuPrev.total;
                if (dt > 0)
                    shell.cpuUsage = 1 - (idle - shell.cpuPrev.idle) / dt;
            }
            shell.cpuPrev = { idle, total };
        }
    }

    FileView {
        id: memInfo
        path: "/proc/meminfo"
        onLoaded: {
            const get = k => Number((text().match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]);
            const total = get("MemTotal"), avail = get("MemAvailable");
            if (total > 0) {
                shell.memUsed = 1 - avail / total;
                const gb = kb => (kb / 1048576).toFixed(1);
                shell.memText = gb(total - avail) + " / " + gb(total) + " ГБ";
            }
        }
    }

    FileView {
        id: loadAvg
        path: "/proc/loadavg"
        onLoaded: shell.loadText = text().split(" ").slice(0, 3).join("  ")
    }

    FileView {
        id: upTime
        path: "/proc/uptime"
        onLoaded: {
            const s = Math.floor(Number(text().split(" ")[0]));
            const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
            shell.uptimeText = (d > 0 ? d + " д " : "") + h + " ч " + m + " мин";
        }
    }

    Process {
        id: topProc
        command: ["ps", "-eo", "comm=,pcpu=", "--sort=-pcpu"]
        stdout: StdioCollector {
            onStreamFinished: shell.topProcs = text.trim().split("\n").slice(0, 3).map(l => {
                const m = l.trim().match(/^(.*\S)\s+([\d.]+)$/);
                return m ? { name: m[1], cpu: Number(m[2]) } : null;
            }).filter(x => x)
        }
    }

    // ===== Погода (Open-Meteo, местоположение по IP) =====
    property string weatherTemp: "--"
    property string weatherDesc: "Загрузка…"
    property int weatherCode: -1
    property string weatherCity: ""
    property string weatherExtra: ""
    property string weatherUpdated: ""
    property var forecast: []                   // [{ date, max, min, code, rain }]

    function weatherText(code) {
        const m = {
            0: "Ясно", 1: "Преимущественно ясно", 2: "Переменная облачность", 3: "Пасмурно",
            45: "Туман", 48: "Изморозь", 51: "Лёгкая морось", 53: "Морось", 55: "Сильная морось",
            56: "Ледяная морось", 57: "Ледяная морось", 61: "Небольшой дождь", 63: "Дождь",
            65: "Сильный дождь", 66: "Ледяной дождь", 67: "Ледяной дождь", 71: "Небольшой снег",
            73: "Снег", 75: "Сильный снег", 77: "Снежная крупа", 80: "Ливень", 81: "Ливень",
            82: "Сильный ливень", 85: "Снегопад", 86: "Сильный снегопад", 95: "Гроза",
            96: "Гроза с градом", 99: "Гроза с градом"
        };
        return m[code] ?? "—";
    }

    function weatherIcon(code) {
        if (code === 0 || code === 1) return "\u{F0599}";      // солнце
        if (code === 2) return "\u{F0595}";                     // переменная облачность
        if (code === 3) return "\u{F0590}";                     // облачно
        if (code === 45 || code === 48) return "\u{F0591}";     // туман
        if (code >= 51 && code <= 67) return code >= 65 ? "\u{F0596}" : "\u{F0597}";
        if (code >= 71 && code <= 77 || code === 85 || code === 86) return "\u{F0598}";
        if (code >= 80 && code <= 82) return "\u{F0596}";       // ливень
        if (code >= 95) return "\u{F0593}";                     // гроза
        return "\u{F0590}";
    }

    function refreshWeather() {
        if (!weatherProc.running)
            weatherProc.running = true;
    }

    Process {
        id: weatherProc
        command: ["sh", "-c",
            "loc=$(curl -sf --max-time 10 'http://ip-api.com/json/?fields=city,lat,lon&lang=ru'); " +
            "lat=$(echo \"$loc\" | sed -n 's/.*\"lat\":\\([-0-9.]*\\).*/\\1/p'); " +
            "lon=$(echo \"$loc\" | sed -n 's/.*\"lon\":\\([-0-9.]*\\).*/\\1/p'); " +
            "w=$(curl -sf --max-time 10 \"https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
            "&current=temperature_2m,apparent_temperature,weather_code,relative_humidity_2m,wind_speed_10m&wind_speed_unit=ms" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=5\"); " +
            "printf '{\"loc\":%s,\"w\":%s}' \"${loc:-null}\" \"${w:-null}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const cur = d.w.current;
                    shell.weatherTemp = Math.round(cur.temperature_2m) + "°";
                    shell.weatherCode = cur.weather_code;
                    shell.weatherDesc = shell.weatherText(cur.weather_code);
                    shell.weatherCity = d.loc?.city ?? "";
                    shell.weatherExtra = "Ощущается " + Math.round(cur.apparent_temperature) + "°  ·  "
                        + cur.relative_humidity_2m + "%  ·  " + Math.round(cur.wind_speed_10m) + " м/с";
                    const dl = d.w.daily;
                    shell.forecast = (dl?.time ?? []).map((t, i) => ({
                        date: t, max: Math.round(dl.temperature_2m_max[i]), min: Math.round(dl.temperature_2m_min[i]),
                        code: dl.weather_code[i], rain: dl.precipitation_probability_max?.[i] ?? null
                    }));
                    shell.weatherUpdated = Qt.formatTime(new Date(), "HH:mm");
                } catch (e) {
                    shell.weatherDesc = "Нет данных";
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            procStat.reload();
            if (shell.cpuDetails) {
                memInfo.reload();
                loadAvg.reload();
                upTime.reload();
                if (!topProc.running)
                    topProc.running = true;
            }
        }
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: shell.refreshWeather()
    }

    // ===== Плеер =====
    // Выбранный вручную плеер (клик по имени плеера), иначе — играющий или первый
    property var pinnedPlayer: null
    readonly property var players: Mpris.players.values
    readonly property var player: {
        const list = players;
        if (pinnedPlayer && list.includes(pinnedPlayer)) return pinnedPlayer;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }

    function cyclePlayer() {
        const list = players;
        if (list.length < 2) return;
        pinnedPlayer = list[(list.indexOf(player) + 1) % list.length];
    }

    function fmtTime(sec) {
        if (!isFinite(sec) || sec < 0) return "0:00";
        sec = Math.floor(sec);
        return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0");
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // ===== Компоненты =====
    component Label: Text {
        font.family: shell.fontFamily
        color: shell.c.onSurface
        elide: Text.ElideRight
        Layout.fillWidth: true
    }

    component Card: Rectangle {
        id: card
        default property alias content: inner.data
        property bool interactive: false        // клик по карточке
        readonly property alias hovered: cardArea.containsMouse
        signal clicked
        signal scrolled(int delta)
        Layout.preferredWidth: shell.cardWidth
        implicitHeight: inner.implicitHeight + 24
        radius: shell.radius
        color: Qt.alpha(interactive && hovered ? shell.c.container : shell.c.surface, shell.cardOpacity)
        border.width: 1
        border.color: interactive && hovered ? Qt.alpha(shell.c.primary, 0.5) : shell.c.outline
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        MouseArea {
            id: cardArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: card.interactive ? Qt.LeftButton : Qt.NoButton
            cursorShape: card.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: card.clicked()
            onWheel: wheel => card.scrolled(wheel.angleDelta.y)
        }

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4
        }
    }

    // Раскрывающийся блок внутри карточки
    component Expander: Item {
        id: ex
        default property alias content: exInner.data
        property bool open: false
        Layout.fillWidth: true
        implicitHeight: open ? exInner.implicitHeight + 8 : 0
        visible: implicitHeight > 0.5
        opacity: open ? 1 : 0
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        ColumnLayout {
            id: exInner
            y: 8
            width: ex.width
            spacing: 4
        }
    }

    component Header: RowLayout {
        property string title
        property string value
        property color accent: shell.c.primary
        Layout.fillWidth: true
        Label {
            text: parent.title
            color: shell.c.variant
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }
        Label {
            text: parent.value
            color: parent.accent
            font.pixelSize: 15
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignRight
        }
    }

    component Bar: Rectangle {
        property real value: 0
        property color accent: shell.c.primary
        Layout.fillWidth: true
        implicitHeight: 4
        radius: 1
        color: shell.c.outline
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: parent.radius
            color: parent.accent
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    // Строка «подпись … значение» для подробностей
    component InfoRow: RowLayout {
        property string label
        property string value
        Layout.fillWidth: true
        Label {
            text: parent.label
            color: shell.c.variant
            font.pixelSize: 11
        }
        Label {
            text: parent.value
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
        }
    }

    component IconButton: Text {
        id: btn
        signal clicked
        property real size: 16
        font.family: shell.iconFont
        font.pixelSize: size
        color: area.containsMouse ? shell.c.primary : shell.c.onSurface
        opacity: enabled ? 1 : 0.35
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Layout.preferredWidth: size + 8
        Layout.preferredHeight: size + 8
        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: btn.enabled
            onClicked: btn.clicked()
        }
    }

    // Кнопка с подписью: для действий и переключателя профилей питания
    component Chip: Rectangle {
        id: chip
        signal clicked
        property string icon
        property string text
        property bool active: false
        Layout.fillWidth: true
        implicitHeight: 24
        radius: shell.radius
        color: active ? Qt.alpha(shell.c.primary, 0.22)
             : chipArea.containsMouse ? Qt.alpha(shell.c.onSurface, 0.08) : "transparent"
        border.width: 1
        border.color: active ? Qt.alpha(shell.c.primary, 0.6) : shell.c.outline
        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            anchors.centerIn: parent
            spacing: 4
            Text {
                visible: chip.icon !== ""
                text: chip.icon
                font.family: shell.iconFont
                font.pixelSize: 12
                color: chip.active ? shell.c.primary : shell.c.onSurface
            }
            Text {
                visible: chip.text !== ""
                text: chip.text
                font.family: shell.fontFamily
                font.pixelSize: 10
                font.weight: chip.active ? Font.DemiBold : Font.Normal
                color: chip.active ? shell.c.primary : shell.c.onSurface
            }
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    // ===== Окна =====
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property bool isPrimary: modelData === shell.primaryScreen
            visible: isPrimary && hmon?.activeWorkspace?.id === (shell.monitorBases[modelData.name] ?? 0) + shell.workspace

            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "desktop-widgets"
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {
                Region { item: leftCol }
                Region { item: rightCol }
            }

            // Публикуем занятые области: иконки рабочего стола hyprstack обходят эти ячейки.
            // Резервируем свёрнутый размер — раскрытые подробности временно перекрывают иконки,
            // а не заставляют их перестраиваться.
            function collapsedHeight(col, exps) {
                return col.height - exps.reduce((a, e) => a + (e.visible ? e.implicitHeight + 4 : 0), 0);
            }
            readonly property string reservedJson: !isPrimary ? "[]" : JSON.stringify([
                [leftCol, [cpuExp]], [rightCol, [calExp, weatherExp]]
            ].map(([c, exps]) => ({
                x: Math.round(c.x), y: Math.round(c.y), w: Math.round(c.width), h: Math.round(collapsedHeight(c, exps))
            })))
            onReservedJsonChanged: reservedTimer.restart()

            Timer {
                id: reservedTimer
                interval: 400
                onTriggered: reservedFile.setText(win.reservedJson)
            }

            FileView {
                id: reservedFile
                path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/hyprstack/desktop-reserved-${win.modelData.name}.json`
                printErrors: false
            }

            // ---- Слева: CPU + батарея ----
            ColumnLayout {
                id: leftCol
                x: shell.edge
                y: shell.top
                spacing: shell.gap

                Card {
                    interactive: true
                    onClicked: {
                        cpuExp.open = !cpuExp.open;
                        shell.cpuDetails = cpuExp.open;
                        if (cpuExp.open) {
                            memInfo.reload();
                            loadAvg.reload();
                            upTime.reload();
                            topProc.running = true;
                        }
                    }

                    Header {
                        title: "ПРОЦЕССОР"
                        value: Math.round(shell.cpuUsage * 100) + "%"
                        accent: shell.cpuUsage > 0.85 ? shell.c.error : shell.c.primary
                    }
                    Bar {
                        value: shell.cpuUsage
                        accent: shell.cpuUsage > 0.85 ? shell.c.error : shell.c.primary
                    }

                    Expander {
                        id: cpuExp

                        Header {
                            title: "ПАМЯТЬ"
                            value: Math.round(shell.memUsed * 100) + "%"
                            accent: shell.memUsed > 0.9 ? shell.c.error : shell.c.tertiary
                        }
                        Bar {
                            value: shell.memUsed
                            accent: shell.memUsed > 0.9 ? shell.c.error : shell.c.tertiary
                        }
                        InfoRow { label: "Занято"; value: shell.memText }
                        InfoRow { label: "Нагрузка"; value: shell.loadText }
                        InfoRow { label: "Работает"; value: shell.uptimeText }

                        Label {
                            Layout.topMargin: 4
                            text: "ТОП ПРОЦЕССОВ"
                            color: shell.c.variant
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                        }
                        Repeater {
                            model: shell.topProcs
                            InfoRow {
                                required property var modelData
                                label: modelData.name
                                value: modelData.cpu.toFixed(1) + "%"
                            }
                        }

                        Chip {
                            Layout.topMargin: 4
                            icon: "\u{F035B}"
                            text: "Открыть btop"
                            onClicked: Quickshell.execDetached(shell.terminal.concat(["btop"]))
                        }
                    }
                }

                Card {
                    id: batCard
                    readonly property var bat: UPower.displayDevice
                    readonly property real pct: bat?.percentage ?? 0
                    readonly property bool charging: bat?.state === UPowerDeviceState.Charging
                        || bat?.state === UPowerDeviceState.FullyCharged
                    readonly property color accent: pct <= 0.15 && !charging ? shell.c.error : shell.c.secondary

                    Header {
                        title: "БАТАРЕЯ"
                        value: Math.round(batCard.pct * 100) + "%"
                        accent: batCard.accent
                    }
                    Bar {
                        value: batCard.pct
                        accent: batCard.accent
                    }
                    Label {
                        readonly property var bat: batCard.bat
                        readonly property real t: batCard.charging ? bat?.timeToFull ?? 0 : bat?.timeToEmpty ?? 0
                        readonly property real rate: Math.abs(bat?.changeRate ?? 0)
                        text: (bat?.state === UPowerDeviceState.FullyCharged ? "Заряжена"
                              : batCard.charging ? "Заряжается" : "От батареи")
                              + (t > 0 ? "  ·  " + Math.floor(t / 3600) + " ч " + Math.floor(t % 3600 / 60) + " мин" : "")
                              + (rate > 0.1 ? "  ·  " + rate.toFixed(1) + " Вт" : "")
                        color: shell.c.variant
                        font.pixelSize: 11
                    }

                    // Профили питания (power-profiles-daemon)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 4

                        Chip {
                            icon: "\u{F032A}"
                            text: "Эконом"
                            active: PowerProfiles.profile === PowerProfile.PowerSaver
                            onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
                        }
                        Chip {
                            icon: "\u{F05D1}"
                            text: "Баланс"
                            active: PowerProfiles.profile === PowerProfile.Balanced
                            onClicked: PowerProfiles.profile = PowerProfile.Balanced
                        }
                        Chip {
                            visible: PowerProfiles.hasPerformanceProfile
                            icon: "\u{F04C5}"
                            text: "Макс"
                            active: PowerProfiles.profile === PowerProfile.Performance
                            onClicked: PowerProfiles.profile = PowerProfile.Performance
                        }
                    }
                }
            }

            // ---- Справа: часы, погода, плеер ----
            ColumnLayout {
                id: rightCol
                x: parent.width - width - shell.edge
                y: shell.top
                spacing: shell.gap

                Card {
                    id: clockCard
                    interactive: true
                    property int monthOffset: 0
                    onClicked: {
                        calExp.open = !calExp.open;
                        monthOffset = 0;
                    }
                    // Колесом листаем месяцы, когда календарь открыт
                    onScrolled: delta => {
                        if (calExp.open && delta !== 0)
                            monthOffset += delta > 0 ? -1 : 1;
                    }

                    Label {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: shell.c.primary
                        font.pixelSize: 40
                        font.weight: Font.Bold
                    }
                    Label {
                        text: {
                            const s = clock.date.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM");
                            return s.charAt(0).toUpperCase() + s.slice(1);
                        }
                        color: shell.c.variant
                        font.pixelSize: 12
                    }

                    Expander {
                        id: calExp
                        readonly property string today: Qt.formatDate(clock.date, "yyyy-MM-dd")
                        readonly property int baseYear: Number(today.slice(0, 4))
                        readonly property int baseMonth: Number(today.slice(5, 7)) - 1
                        readonly property date first: new Date(baseYear, baseMonth + clockCard.monthOffset, 1)
                        readonly property int lead: (first.getDay() + 6) % 7   // неделя с понедельника

                        RowLayout {
                            Layout.fillWidth: true
                            IconButton {
                                text: "\u{F0141}"
                                size: 14
                                onClicked: clockCard.monthOffset--
                            }
                            Label {
                                text: {
                                    const s = calExp.first.toLocaleDateString(Qt.locale("ru_RU"), "LLLL yyyy");
                                    return s.charAt(0).toUpperCase() + s.slice(1);
                                }
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: clockCard.monthOffset !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: clockCard.monthOffset = 0
                                }
                            }
                            IconButton {
                                text: "\u{F0142}"
                                size: 14
                                onClicked: clockCard.monthOffset++
                            }
                        }

                        Grid {
                            id: calGrid
                            Layout.fillWidth: true
                            columns: 7
                            readonly property real cell: width / 7

                            Repeater {
                                model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                                Text {
                                    required property string modelData
                                    required property int index
                                    width: calGrid.cell
                                    height: 20
                                    text: modelData
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.family: shell.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: index >= 5 ? shell.c.primary : shell.c.variant
                                }
                            }
                            Repeater {
                                model: 42
                                Rectangle {
                                    required property int index
                                    readonly property date d: new Date(calExp.first.getFullYear(), calExp.first.getMonth(), index - calExp.lead + 1)
                                    readonly property bool inMonth: d.getMonth() === calExp.first.getMonth()
                                    readonly property bool isToday: Qt.formatDate(d, "yyyy-MM-dd") === calExp.today
                                    width: calGrid.cell
                                    height: 22
                                    radius: shell.radius
                                    color: isToday ? shell.c.primary : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.d.getDate()
                                        font.family: shell.fontFamily
                                        font.pixelSize: 11
                                        font.weight: parent.isToday ? Font.Bold : Font.Normal
                                        color: parent.isToday ? shell.c.surface
                                             : !parent.inMonth ? Qt.alpha(shell.c.variant, 0.4)
                                             : (parent.index % 7) >= 5 ? shell.c.primary : shell.c.onSurface
                                    }
                                }
                            }
                        }
                    }
                }

                Card {
                    interactive: true
                    onClicked: weatherExp.open = !weatherExp.open

                    Header {
                        title: shell.weatherCity ? "ПОГОДА · " + shell.weatherCity.toUpperCase() : "ПОГОДА"
                        value: shell.weatherTemp
                        accent: shell.c.tertiary
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            visible: shell.weatherCode >= 0
                            text: shell.weatherIcon(shell.weatherCode)
                            font.family: shell.iconFont
                            font.pixelSize: 15
                            color: shell.c.tertiary
                        }
                        Label {
                            text: shell.weatherDesc
                            font.pixelSize: 13
                        }
                    }
                    Label {
                        visible: shell.weatherExtra !== ""
                        text: shell.weatherExtra
                        color: shell.c.variant
                        font.pixelSize: 11
                    }

                    Expander {
                        id: weatherExp

                        Repeater {
                            model: shell.forecast
                            RowLayout {
                                id: day
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 6
                                Label {
                                    Layout.fillWidth: false
                                    Layout.preferredWidth: 62
                                    text: {
                                        if (day.index === 0) return "Сегодня";
                                        if (day.index === 1) return "Завтра";
                                        const s = new Date(day.modelData.date + "T12:00").toLocaleDateString(Qt.locale("ru_RU"), "ddd, d");
                                        return s.charAt(0).toUpperCase() + s.slice(1);
                                    }
                                    color: day.index === 0 ? shell.c.onSurface : shell.c.variant
                                    font.pixelSize: 11
                                }
                                Text {
                                    Layout.preferredWidth: 18
                                    text: shell.weatherIcon(day.modelData.code)
                                    font.family: shell.iconFont
                                    font.pixelSize: 13
                                    color: shell.c.tertiary
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Label {
                                    text: day.modelData.rain !== null && day.modelData.rain >= 20 ? "\u{F058C} " + day.modelData.rain + "%" : ""
                                    font.family: shell.iconFont
                                    color: shell.c.variant
                                    font.pixelSize: 10
                                }
                                Label {
                                    Layout.fillWidth: false
                                    text: day.modelData.max + "° / " + day.modelData.min + "°"
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            Label {
                                text: weatherProc.running ? "Обновляется…"
                                    : shell.weatherUpdated ? "Обновлено в " + shell.weatherUpdated : ""
                                color: shell.c.variant
                                font.pixelSize: 10
                            }
                            IconButton {
                                text: "\u{F0450}"
                                size: 13
                                enabled: !weatherProc.running
                                onClicked: shell.refreshWeather()
                            }
                        }
                    }
                }

                Card {
                    id: mediaCard
                    visible: shell.player !== null
                    readonly property var p: shell.player
                    // Firefox для стримов отдаёт мусорную длину — считаем её неизвестной
                    readonly property bool hasLength: (p?.lengthSupported ?? false)
                        && (p?.length ?? 0) > 0 && p.length < 7 * 24 * 3600
                    readonly property bool canVolume: (p?.volumeSupported ?? false) && (p?.canControl ?? false)
                    // Иконка приложения плеера, если у трека нет обложки
                    readonly property string appIcon: {
                        const e = p?.desktopEntry ? DesktopEntries.heuristicLookup(p.desktopEntry) : null;
                        return e?.icon ? Quickshell.iconPath(e.icon, true) : "";
                    }
                    property bool showVolume: false

                    // Колесо над карточкой — громкость плеера
                    onScrolled: delta => {
                        if (!canVolume || delta === 0) return;
                        p.volume = Math.max(0, Math.min(1, p.volume + (delta > 0 ? 0.05 : -0.05)));
                        showVolume = true;
                        volumeHide.restart();
                    }

                    Timer {
                        id: volumeHide
                        interval: 1500
                        onTriggered: mediaCard.showVolume = false
                    }

                    Timer {
                        interval: 1000
                        running: mediaCard.visible && (mediaCard.p?.isPlaying ?? false)
                        repeat: true
                        onTriggered: mediaCard.p?.positionChanged()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: mediaCard.p?.isPlaying ? "СЕЙЧАС ИГРАЕТ" : "НА ПАУЗЕ"
                            color: shell.c.variant
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                        }
                        // Имя плеера; при нескольких плеерах клик переключает между ними
                        Label {
                            readonly property bool multi: shell.players.length > 1
                            text: mediaCard.showVolume ? "\u{F057E} " + Math.round((mediaCard.p?.volume ?? 0) * 100) + "%"
                                : (mediaCard.p?.identity ?? "") + (multi ? "  \u{F04E1}" : "")
                            color: switchArea.containsMouse && multi ? shell.c.primary : shell.c.variant
                            font.family: shell.iconFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignRight
                            MouseArea {
                                id: switchArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: parent.multi
                                cursorShape: Qt.PointingHandCursor
                                onClicked: shell.cyclePlayer()
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 10

                        // Обложка трека → иконка приложения → нота. Клик — показать окно плеера
                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: shell.radius
                            color: shell.c.container
                            clip: true
                            border.width: coverArea.containsMouse && mediaCard.p?.canRaise ? 1 : 0
                            border.color: shell.c.primary

                            Image {
                                id: cover
                                anchors.fill: parent
                                source: mediaCard.p?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(88, 88)
                                visible: status === Image.Ready
                            }
                            Image {
                                id: appIcon
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                source: cover.visible ? "" : mediaCard.appIcon
                                sourceSize: Qt.size(56, 56)
                                visible: !cover.visible && status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !cover.visible && !appIcon.visible
                                text: "\u{F075A}"
                                font.family: shell.iconFont
                                font.pixelSize: 22
                                color: shell.c.primary
                            }
                            MouseArea {
                                id: coverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: mediaCard.p?.canRaise ?? false
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mediaCard.p.raise()
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                text: mediaCard.p?.trackTitle || "Без названия"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Label {
                                visible: text !== ""
                                text: mediaCard.p?.trackArtist ?? ""
                                color: shell.c.variant
                                font.pixelSize: 11
                            }
                        }
                    }
                    // Полоса прогресса: клик или перетаскивание — перемотка
                    Item {
                        id: seek
                        visible: mediaCard.hasLength
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        implicitHeight: 10
                        readonly property bool canSeek: mediaCard.p?.canSeek ?? false
                        property real dragFrac: -1

                        Bar {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            implicitHeight: seekArea.containsMouse && seek.canSeek ? 6 : 4
                            value: seek.dragFrac >= 0 ? seek.dragFrac
                                : mediaCard.hasLength ? mediaCard.p.position / mediaCard.p.length : 0
                            accent: shell.c.secondary
                            Behavior on implicitHeight { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: seek.canSeek
                            cursorShape: Qt.PointingHandCursor
                            function frac(x) { return Math.max(0, Math.min(1, x / width)); }
                            onPressed: mouse => seek.dragFrac = frac(mouse.x)
                            onPositionChanged: mouse => { if (pressed) seek.dragFrac = frac(mouse.x); }
                            onReleased: {
                                mediaCard.p.position = seek.dragFrac * mediaCard.p.length;
                                seek.dragFrac = -1;
                            }
                            onCanceled: seek.dragFrac = -1
                        }
                    }
                    // Время по краям, кнопки управления по центру
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            text: !mediaCard.hasLength ? ""
                                : shell.fmtTime(seek.dragFrac >= 0 ? seek.dragFrac * mediaCard.p.length : mediaCard.p?.position ?? 0)
                            color: shell.c.variant
                            font.pixelSize: 10
                        }
                        IconButton {
                            text: "\u{F04AE}"
                            enabled: mediaCard.p?.canGoPrevious ?? false
                            onClicked: mediaCard.p.previous()
                        }
                        IconButton {
                            text: mediaCard.p?.isPlaying ? "\u{F03E4}" : "\u{F040A}"
                            size: 20
                            enabled: mediaCard.p?.canTogglePlaying ?? false
                            onClicked: mediaCard.p.togglePlaying()
                        }
                        IconButton {
                            text: "\u{F04AD}"
                            enabled: mediaCard.p?.canGoNext ?? false
                            onClicked: mediaCard.p.next()
                        }
                        Label {
                            text: mediaCard.hasLength ? shell.fmtTime(mediaCard.p?.length ?? 0) : ""
                            color: shell.c.variant
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
}
