//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs

ShellRoot {
    id: root
    property string page: ""
    onPageChanged: focusTimer.restart()
    Timer {
        id: focusTimer
        interval: 50
        onTriggered: {
            if (root.page === "overview") windows.forceActiveFocus();
            else if (root.page !== "") panelContent.forceActiveFocus();
        }
    }
    property bool inhibitIdle: false
    property bool barVisible: true
    property bool barBottom: false
    property bool desktopClockVisible: true
    property bool toolsDetached: false
    property bool keyboardVisible: false
    property bool keyboardShift: false
    property bool keyboardControl: false
    property var preferences: ({})
    property var userState: ({})
    property bool light: userState.light === true
    property var palette: ({})
    property string uiFont: preferences.font || "DejaVu Sans"
    property color surface: palette.surface || (light ? "#fff8fc" : "#141313")
    property color raised: palette.raised || (light ? "#ece6eb" : "#1c1b1c")
    property color ink: palette.ink || (light ? "#1d1b20" : "#e6e1e1")
    property color accent: palette.accent || (light ? "#615d63" : "#cbc4cb")
    property string wallpaper: profile + "/theme/wallpaper.png"
    property int wallpaperRevision: 0
    property int clockRevision: 0
    property string profile: Quickshell.shellDir + "/.."
    property var status: ({volume: "—", network: "—", brightness: false})
    function action(name) { Quickshell.execDetached([profile + "/bin/desktop-action", name]); }
    function toggle(name) { page = page === name ? "" : name; }
    function workspace(number) { Hyprland.dispatch("hl.dsp.focus({workspace=" + number + "})"); }
    function workspaceStart(active, count) { return Math.floor((Math.max(1, active || 1) - 1) / count) * count + 1; }
    function control(name) {
        if (name === "bar") barVisible = !barVisible;
        else if (name === "bar-position") barBottom = !barBottom;
        else if (name === "widgets") desktopClockVisible = !desktopClockVisible;
        else if (name === "keyboard") keyboardVisible = !keyboardVisible;
        else if (name === "keep-awake") inhibitIdle = !inhibitIdle;
        else if (name === "detach-tools") { page = ""; toolsDetached = !toolsDetached; }
    }
    function utility(name) { page = ""; toolsDetached = false; action(name); }
    function typeKey(key) {
        if (key === "Shift") { keyboardShift = !keyboardShift; return; }
        if (key === "Ctrl") { keyboardControl = !keyboardControl; return; }
        const mods = [keyboardShift ? "SHIFT" : "", keyboardControl ? "CTRL" : ""].filter(Boolean).join(" + ");
        Hyprland.dispatch("hl.dsp.send_shortcut({mods=" + JSON.stringify(mods) + ",key=" + JSON.stringify(key) + "})");
        keyboardShift = false;
    }
    FileView {
        path: root.profile + "/preferences.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.preferences = JSON.parse(text()); } catch (e) { console.warn(e); } }
    }
    FileView {
        path: root.profile + "/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.userState = JSON.parse(text()); root.wallpaperRevision++; } catch (e) { console.warn(e); } }
    }
    FileView {
        path: root.profile + "/theme/palette.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.palette = JSON.parse(text()); if (!clockProcess.running) clockProcess.running = true; }
            catch (e) { console.warn(e); }
        }
    }
    Process {
        id: clockProcess
        command: [root.profile + "/bin/lock-visuals", "clock"]
        stdout: StdioCollector { onStreamFinished: root.clockRevision++ }
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: if (!clockProcess.running) clockProcess.running = true }
    Process {
        id: statusProcess
        command: [root.profile + "/bin/desktop-action", "status"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.status = JSON.parse(text); } catch (e) { console.warn(e); } }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: statusProcess.running = true }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    IpcHandler {
        target: "desktop"
        function toggle(name: string): void { root.toggle(name); }
        function control(name: string): void { root.control(name); }
        function key(key: string): void { root.typeKey(key); }
        function awake(active: bool): void { root.inhibitIdle = active; }
        function status(): string {
            return JSON.stringify({page: root.page, windows: ToplevelManager.toplevels.values.length,
                hyprlandWindows: Hyprland.toplevels.values.length, screens: Quickshell.screens.length,
                overviewFocus: windows.activeFocus, selectedWindow: windows.currentIndex,
                barVisible: root.barVisible, barBottom: root.barBottom,
                widgetsVisible: root.desktopClockVisible, keyboardVisible: root.keyboardVisible,
                toolsDetached: root.toolsDetached, idleInhibited: root.inhibitIdle});
        }
    }

    component Chip: Button {
        id: chip
        property bool selected: false
        property bool urgent: false
        padding: 0
        implicitHeight: 30
        implicitWidth: Math.max(34, contentItem.implicitWidth + 22)
        hoverEnabled: true
        background: Rectangle {
            radius: height / 2
            color: chip.selected ? root.accent : (chip.hovered || chip.activeFocus ? root.raised : "transparent")
            border.width: chip.activeFocus || chip.urgent ? 2 : 0
            border.color: root.accent
        }
        contentItem: Text {
            text: chip.text; color: chip.selected ? root.surface : root.ink
            font.family: root.uiFont; font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    FloatingWindow {
        visible: root.toolsDetached
        onVisibleChanged: if (!visible) root.toolsDetached = false
        title: "Desktop utilities"
        implicitWidth: 420; implicitHeight: 520
        color: root.surface
        ToolsContent { desktop: root; anchors.fill: parent; anchors.margins: 20 }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: desktopBackground
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            IdleInhibitor { window: desktopBackground; enabled: root.inhibitIdle }
            color: root.surface
            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: "file://" + root.wallpaper + "?v=" + root.wallpaperRevision; cache: false }
            Image {
                visible: root.desktopClockVisible
                width: 230; height: 230
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: 70; bottomMargin: 70 }
                source: root.clockRevision > 0 ? "file://" + root.profile + "/theme/clock.png?v=" + root.clockRevision : ""
                cache: false
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: root.barVisible
            anchors { top: !root.barBottom; bottom: root.barBottom; left: true; right: true }
            implicitHeight: 40
            color: root.surface
            WlrLayershell.namespace: "archsetup-panel"
            Row {
                id: barCenter
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    width: workspaceRow.implicitWidth + 12; height: 32; radius: 16; color: root.raised
                    Row {
                        id: workspaceRow
                        readonly property int workspaceCount: panel.width > 1100 ? 10 : 5
                        readonly property int firstWorkspace: root.workspaceStart(Hyprland.monitorFor(panel.screen)?.activeWorkspace?.id, workspaceCount)
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: workspaceRow.workspaceCount
                            Chip {
                                required property int index
                                readonly property int workspaceId: workspaceRow.firstWorkspace + index
                                implicitWidth: Math.max(26, contentItem.implicitWidth + 10); implicitHeight: 26
                                text: String(workspaceId)
                                selected: Hyprland.monitorFor(panel.screen)?.activeWorkspace?.id === workspaceId
                                onClicked: root.workspace(workspaceId)
                            }
                        }
                    }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.toggle("overview") }
                }
                Rectangle {
                    width: timeRow.implicitWidth + 12; height: 32; radius: 16; color: root.raised
                    RowLayout {
                        id: timeRow
                        anchors.centerIn: parent
                        spacing: 4
                        Chip { text: Qt.formatDateTime(clock.date, panel.width > 1100 ? "HH:mm · d MMM" : "HH:mm"); onClicked: root.toggle("settings") }
                        Chip {
                            visible: UPower.displayDevice.isLaptopBattery
                            text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                            onClicked: root.toggle("settings")
                        }
                    }
                }
            }
            RowLayout {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 12 }
                spacing: 4
                Repeater {
                    model: panel.screen === Quickshell.screens[0] ? SystemTray.items : null
                    delegate: Chip {
                        id: trayButton
                        required property var modelData
                        implicitWidth: 30
                        Image { anchors.centerIn: parent; width: 18; height: 18; source: trayButton.modelData.icon }
                        Accessible.name: modelData.title
                        onClicked: modelData.onlyMenu ? modelData.display(panel, x, y) : modelData.activate()
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: trayButton.modelData.display(panel, trayButton.x, trayButton.y) }
                    }
                }
                Chip { text: root.status.volume; visible: panel.width > 1000; onClicked: root.toggle("settings") }
                Chip { text: "●"; Accessible.name: "Notifications"; onClicked: root.action("notifications") }
                Chip { text: "Power"; Accessible.name: "Session"; onClicked: root.toggle("session") }
            }
        }
    }

    PanelWindow {
        id: overlay
        visible: root.page !== ""
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: root.page = "" }
        Rectangle {
            width: Math.min(parent.width - 48, root.page === "overview" ? 1000 : 540)
            height: Math.min(parent.height - 80, root.page === "overview" ? 700 : 560)
            anchors.centerIn: parent; radius: 24; color: root.surface
            // Consume clicks inside the surface so only the backdrop dismisses it.
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 24; spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: root.page === "overview" ? "Your windows" : root.page === "settings" ? "Quick settings" : root.page === "tools" ? "Utilities" : root.page === "media" ? "Media" : "Session"; color: root.ink; font.family: root.uiFont; font.pixelSize: 24; Layout.fillWidth: true }
                    Chip { text: "Close"; onClicked: root.page = "" }
                }
                Item {
                    id: panelContent
                    Layout.fillWidth: true; Layout.fillHeight: true
                    focus: overlay.visible
                    Keys.onEscapePressed: root.page = ""
                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.page === "overview" ? 0 : root.page === "settings" ? 1 : root.page === "tools" ? 3 : root.page === "media" ? 4 : 2
                        ColumnLayout {
                            RowLayout {
                                id: overviewWorkspaces
                                readonly property int firstWorkspace: root.workspaceStart(Hyprland.monitorFor(overlay.screen)?.activeWorkspace?.id, 10)
                                Repeater {
                                    model: 10
                                    Chip {
                                        required property int index
                                        readonly property int workspaceId: overviewWorkspaces.firstWorkspace + index
                                        text: String(workspaceId)
                                        selected: Hyprland.monitorFor(overlay.screen)?.activeWorkspace?.id === workspaceId
                                        onClicked: { root.workspace(workspaceId); root.page = ""; }
                                    }
                                }
                            }
                            GridView {
                                id: windows
                                Layout.fillWidth: true; Layout.fillHeight: true
                                clip: true; cellWidth: width > 700 ? width / 3 : width / 2; cellHeight: 200
                                model: ToplevelManager.toplevels
                                focus: root.page === "overview"
                                keyNavigationEnabled: true
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        const selected = ToplevelManager.toplevels.values[Math.max(0, currentIndex)];
                                        if (selected) { selected.activate(); root.page = ""; }
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        root.page = "";
                                        event.accepted = true;
                                    }
                                }
                                delegate: Rectangle {
                                    id: windowCard
                                    required property var modelData
                                    required property int index
                                    width: windows.cellWidth - 10; height: 190; radius: 16; color: root.raised
                                    border.width: windows.currentIndex === index ? 2 : 0; border.color: root.accent
                                    ScreencopyView { anchors { top: parent.top; left: parent.left; right: parent.right; bottom: title.top; margins: 8 } captureSource: windowCard.modelData; live: overlay.visible }
                                    Text { id: title; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 } text: windowCard.modelData.title; font.family: root.uiFont; color: root.ink; elide: Text.ElideRight }
                                    MouseArea { anchors.fill: parent; onClicked: { windowCard.modelData.activate(); root.page = ""; } }
                                }
                            }
                            Text { visible: windows.count === 0; text: "No open windows · Super+Enter opens a terminal"; color: root.ink }
                        }
                        ColumnLayout {
                            spacing: 12
                            Text { text: root.status.network + "  ·  Volume " + root.status.volume; color: root.ink; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Flow {
                                Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 8
                                Chip { text: "Volume −"; onClicked: Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]) }
                                Chip { text: "Volume +"; onClicked: Quickshell.execDetached(["wpctl", "set-volume", "-l", "1", "@DEFAULT_AUDIO_SINK@", "5%+"]) }
                                Chip { text: "Mute"; onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]) }
                                Chip { text: "Microphone"; onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]) }
                                Chip { text: "Audio devices"; onClicked: root.action("audio") }
                                Chip { text: "Network"; onClicked: root.action("network") }
                                Chip { text: "Bluetooth"; onClicked: root.action("bluetooth") }
                                Chip { text: "Brightness −"; visible: root.status.brightness; onClicked: Quickshell.execDetached(["brightnessctl", "-n2", "set", "5%-"]) }
                                Chip { text: "Brightness +"; visible: root.status.brightness; onClicked: Quickshell.execDetached(["brightnessctl", "set", "5%+"]) }
                                Chip { text: "Do not disturb"; onClicked: root.action("dnd") }
                                Chip { text: "Keep awake"; selected: root.inhibitIdle; onClicked: root.inhibitIdle = !root.inhibitIdle }
                                Chip { text: "Light / dark"; onClicked: root.action("theme") }
                                Chip { text: "Calculator"; onClicked: { root.page = ""; root.action("calculator"); } }
                                Chip { text: "Wallpaper"; onClicked: { root.page = ""; root.action("wallpaper"); } }
                                Chip { text: "Previous"; onClicked: Quickshell.execDetached(["playerctl", "previous"]) }
                                Chip { text: "Play / pause"; onClicked: Quickshell.execDetached(["playerctl", "play-pause"]) }
                                Chip { text: "Next"; onClicked: Quickshell.execDetached(["playerctl", "next"]) }
                                Chip { text: "Keyboard"; onClicked: { root.page = ""; root.control("keyboard"); } }
                            }
                            Item { Layout.fillHeight: true }
                            Text { text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy"); color: root.ink }
                        }
                        ColumnLayout {
                            spacing: 10
                            Repeater {
                                model: ["lock", "suspend", "logout", "reboot", "poweroff"]
                                Chip { required property string modelData; text: modelData === "poweroff" ? "Shutdown" : modelData.charAt(0).toUpperCase() + modelData.slice(1); Layout.fillWidth: true; onClicked: { root.page = ""; root.action(modelData); } }
                            }
                            Item { Layout.fillHeight: true }
                        }
                        ToolsContent { desktop: root }
                        ColumnLayout {
                            spacing: 16
                            Text { text: root.status.media || "Nothing playing"; textFormat: Text.PlainText; color: root.ink; font.family: root.uiFont; font.pixelSize: 20; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            RowLayout {
                                Chip { text: "Previous"; onClicked: Quickshell.execDetached(["playerctl", "previous"]) }
                                Chip { text: "Play / pause"; onClicked: Quickshell.execDetached(["playerctl", "play-pause"]) }
                                Chip { text: "Next"; onClicked: Quickshell.execDetached(["playerctl", "next"]) }
                            }
                            Chip { text: "Audio devices"; onClicked: root.action("audio") }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        visible: root.keyboardVisible
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0]
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 250
        color: root.surface
        WlrLayershell.namespace: "archsetup-keyboard"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 5
            RowLayout {
                Text { text: "Keyboard"; color: root.ink; font.family: root.uiFont; Layout.fillWidth: true }
                Chip { text: "Close"; onClicked: root.keyboardVisible = false }
            }
            Repeater {
                model: [
                    ["Escape", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "minus", "equal", "BackSpace"],
                    ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "bracketleft", "bracketright"],
                    ["a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon", "apostrophe", "Return"],
                    ["Shift", "z", "x", "c", "v", "b", "n", "m", "comma", "period", "slash", "Ctrl"],
                    ["Left", "Down", "space", "Up", "Right"]
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 4
                    Repeater {
                        model: parent.modelData
                        Chip {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.minimumWidth: 22
                            text: ({minus: "−", equal: "=", bracketleft: "[", bracketright: "]", semicolon: ";", apostrophe: "'", comma: ",", period: ".", slash: "/", space: "Space", Return: "Enter", BackSpace: "⌫"})[modelData] || (root.keyboardShift && modelData.length === 1 ? modelData.toUpperCase() : modelData)
                            selected: modelData === "Shift" && root.keyboardShift || modelData === "Ctrl" && root.keyboardControl
                            onClicked: root.typeKey(modelData)
                        }
                    }
                }
            }
        }
    }
}
