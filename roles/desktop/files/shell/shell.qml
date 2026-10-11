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
    property var preferences: ({})
    property var userState: ({})
    property bool light: userState.light === true
    property color surface: light ? "#f4eef9" : "#191620"
    property color raised: light ? "#e6dced" : "#292332"
    property color ink: light ? "#251e2d" : "#eae0f5"
    property color accent: userState.accent || (light ? "#69488b" : "#c4a7e7")
    property string profile: Quickshell.shellDir + "/.."
    property var status: ({volume: "—", network: "—", brightness: false})
    function action(name) { Quickshell.execDetached([profile + "/bin/desktop-action", name]); }
    function toggle(name) { page = page === name ? "" : name; }
    function workspace(number) { Hyprland.dispatch("hl.dsp.focus({workspace=" + number + "})"); }
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
        onLoaded: { try { root.userState = JSON.parse(text()); } catch (e) { console.warn(e); } }
    }
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
        function status(): string {
            return JSON.stringify({page: root.page, windows: ToplevelManager.toplevels.values.length,
                hyprlandWindows: Hyprland.toplevels.values.length, screens: Quickshell.screens.length,
                overviewFocus: windows.activeFocus, selectedWindow: windows.currentIndex});
        }
    }

    component Chip: Button {
        id: chip
        property bool selected: false
        property bool urgent: false
        implicitHeight: 34
        implicitWidth: Math.max(34, contentItem.implicitWidth + 22)
        hoverEnabled: true
        background: Rectangle {
            radius: 12
            color: chip.selected ? root.accent : (chip.hovered || chip.activeFocus ? root.raised : "transparent")
            border.width: chip.activeFocus || chip.urgent ? 2 : 0
            border.color: root.accent
        }
        contentItem: Text {
            text: chip.text; color: chip.selected ? root.surface : root.ink
            font.family: "DejaVu Sans"; font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            color: root.surface
            Rectangle {
                anchors.fill: parent
                gradient: Gradient { GradientStop { position: 0; color: root.raised } GradientStop { position: 1; color: root.surface } }
            }
            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: root.userState.wallpaper ? "file://" + root.userState.wallpaper : "" }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            anchors { bottom: true; left: true; right: true }
            implicitHeight: 52
            color: "transparent"
            WlrLayershell.namespace: "archsetup-panel"
            IdleInhibitor { window: panel; enabled: root.inhibitIdle }
            Rectangle {
                anchors.fill: parent; anchors.margins: 4
                radius: 16; color: root.surface
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 4
                    Chip { text: "Apps"; onClicked: root.action("launcher") }
                    Chip { text: "View"; Accessible.name: "Overview"; onClicked: root.toggle("overview") }
                    Repeater {
                        model: 10
                        Chip {
                            required property int index
                            text: String(index + 1)
                            selected: Hyprland.monitorFor(panel.screen)?.activeWorkspace?.id === index + 1
                            onClicked: root.workspace(index + 1)
                            visible: panel.width > 1100 || index < 5
                        }
                    }
                    Chip { text: "Web"; onClicked: root.action("browser") }
                    Chip { text: "Files"; visible: panel.width > 900; onClicked: root.action("files") }
                    ListView {
                        Layout.fillWidth: true; Layout.preferredHeight: 34
                        orientation: ListView.Horizontal; spacing: 4; clip: true
                        model: ToplevelManager.toplevels
                        delegate: Chip {
                            id: taskButton
                            required property var modelData
                            width: 140; text: modelData.title || modelData.appId
                            selected: modelData.activated
                            urgent: Hyprland.toplevels.values.some(t => t.wayland === taskButton.modelData && t.urgent)
                            onClicked: modelData.activate()
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.title
                            TapHandler { acceptedButtons: Qt.RightButton; onTapped: windowMenu.popup() }
                            Menu { id: windowMenu; MenuItem { text: "Close window"; onTriggered: taskButton.modelData.close() } }
                        }
                    }
                    Repeater {
                        model: panel.screen === Quickshell.screens[0] ? SystemTray.items : null
                        delegate: Chip {
                            id: trayButton
                            required property var modelData
                            implicitWidth: 32
                            Image { anchors.centerIn: parent; width: 20; height: 20; source: trayButton.modelData.icon }
                            Accessible.name: modelData.title
                            onClicked: modelData.onlyMenu ? modelData.display(panel, x, y) : modelData.activate()
                            TapHandler { acceptedButtons: Qt.RightButton; onTapped: trayButton.modelData.display(panel, trayButton.x, trayButton.y) }
                        }
                    }
                    Chip {
                        visible: UPower.displayDevice.isLaptopBattery
                        text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                        onClicked: root.toggle("settings")
                    }
                    Chip { text: root.status.volume; visible: panel.width > 900; onClicked: root.toggle("settings") }
                    Chip { text: "●"; Accessible.name: "Notifications"; onClicked: root.action("notifications") }
                    Chip { text: Qt.formatDateTime(clock.date, "ddd HH:mm"); onClicked: root.toggle("settings") }
                    Chip { text: "Power"; Accessible.name: "Session"; onClicked: root.toggle("session") }
                }
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
                    Text { text: root.page === "overview" ? "Your windows" : root.page === "settings" ? "Quick settings" : "Session"; color: root.ink; font.pixelSize: 24; Layout.fillWidth: true }
                    Chip { text: "Close"; onClicked: root.page = "" }
                }
                Item {
                    id: panelContent
                    Layout.fillWidth: true; Layout.fillHeight: true
                    focus: overlay.visible
                    Keys.onEscapePressed: root.page = ""
                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.page === "overview" ? 0 : root.page === "settings" ? 1 : 2
                        ColumnLayout {
                            RowLayout {
                                Repeater { model: 10; Chip { required property int index; text: String(index + 1); onClicked: { root.workspace(index + 1); root.page = ""; } } }
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
                                    Text { id: title; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 } text: windowCard.modelData.title; color: root.ink; elide: Text.ElideRight }
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
                            }
                            Item { Layout.fillHeight: true }
                            Text { text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy"); color: root.ink }
                        }
                        ColumnLayout {
                            spacing: 10
                            Repeater {
                                model: ["lock", "suspend", "logout", "reboot", "poweroff"]
                                Chip { required property string modelData; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); Layout.fillWidth: true; onClicked: { root.page = ""; root.action(modelData); } }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }
    }
}
