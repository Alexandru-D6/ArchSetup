pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: center
    property color surface: "#fff8f9"
    property color raised: "#ffe7eb"
    property color textColor: "#3d2c32"
    property color accent: "#bd0056"
    property color accentText: "white"
    property string uiFont: "DejaVu Sans"
    property var snapshot: ({})
    property bool busy: false
    property string busyAction: ""
    property string error: ""
    property bool nightEnabled: false
    property bool dnd: false
    property var notifications: []
    property bool audioDetails: false
    property bool vpnDetails: false
    property bool wifiDetails: false
    property bool bluetoothDetails: false
    property bool bluetoothReady: false
    property bool bluetoothBusy: false
    property string bluetoothOperation: ""
    property string bluetoothError: ""
    property var bluetoothPrompt: null
    property bool vpnBusy: false
    property string vpnOperation: ""
    property string vpnError: ""
    readonly property var output: (snapshot.outputs || []).find(device => device.id === snapshot.output)
    readonly property var input: (snapshot.inputs || []).find(device => device.id === snapshot.input)
    signal closed()
    signal settingsRequested()
    signal powerRequested()
    signal controlRequested(string action, var value)
    signal wifiDeviceRequested(string device)
    signal bluetoothRequested(string action, var value)
    signal vpnRequested(string action, var value)
    signal vpnRefreshRequested()
    signal launchRequested(string action)
    signal nightRequested()
    signal dndRequested()
    signal clearRequested()
    implicitWidth: 420
    implicitHeight: 900
    Keys.onEscapePressed: { if (wifiDetails) wifiDetails = false; else if (bluetoothDetails) bluetoothDetails = false; else if (vpnDetails) vpnDetails = false; else closed(); }
    onVisibleChanged: if (!visible) { wifiDetails = false; bluetoothDetails = false; vpnDetails = false; }
    onWifiDetailsChanged: Qt.callLater(scrollToTop)
    onBluetoothDetailsChanged: Qt.callLater(scrollToTop)
    onVpnDetailsChanged: Qt.callLater(scrollToTop)
    function scrollToTop() {
        const view = actionScroll.contentItem as Flickable;
        if (view) view.contentY = 0;
    }
    function openWifi() {
        vpnDetails = false;
        bluetoothDetails = false;
        wifiDetails = true;
        if (snapshot.wifiEnabled && !snapshot.wifiScanning && !busy)
            controlRequested("wifi-scan", {device: snapshot.wifiDevice});
    }
    function openBluetooth() { wifiDetails = false; vpnDetails = false; bluetoothDetails = true; }
    function openVpn() { wifiDetails = false; bluetoothDetails = false; vpnDetails = true; vpnRefreshRequested(); }
    function uptime(seconds) {
        const minutes = Math.floor((seconds || 0) / 60);
        const hours = Math.floor(minutes / 60);
        return "Up " + (hours >= 24 ? Math.floor(hours / 24) + "d " : "") + (hours % 24) + "h " + (minutes % 60) + "m";
    }
    component IconButton: Button {
        id: button
        required property string symbol
        implicitWidth: 38; implicitHeight: 38
        background: Rectangle { radius: 19; color: button.hovered || button.visualFocus ? center.accent : center.raised }
        contentItem: SessionIcon { name: button.symbol; implicitWidth: 20; implicitHeight: 20; color: button.hovered || button.visualFocus ? center.accentText : center.textColor }
        ToolTip.visible: hovered
        ToolTip.text: Accessible.name
    }
    Rectangle { anchors.fill: parent; radius: 26; color: center.surface; border.width: 1; border.color: Qt.alpha(center.accent, 0.18) }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 18; spacing: 16
        // 1. Session header.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ColumnLayout {
                Layout.fillWidth: true; spacing: 5
                Text { text: "Control center"; font.family: center.uiFont; font.pixelSize: 19; font.weight: Font.DemiBold; color: center.textColor; Layout.fillWidth: true; elide: Text.ElideRight }
                Text { objectName: "uptime"; text: center.uptime(center.snapshot.uptime); font.family: center.uiFont; font.pixelSize: 12; color: center.textColor; opacity: 0.65 }
            }
            IconButton { objectName: "settings"; symbol: "settings"; Accessible.name: "Settings"; onClicked: center.settingsRequested() }
            IconButton { objectName: "power"; symbol: "poweroff"; Accessible.name: "Power and session"; onClicked: center.powerRequested() }
            IconButton { objectName: "close"; symbol: "close"; Accessible.name: "Close control center"; onClicked: center.closed() }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: center.raised }
        // 2. Quick actions. Scroll independently on smaller displays.
        ScrollView {
            id: actionScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(actions.implicitHeight, Math.max(160, center.height * 0.52))
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                id: actions
                width: parent.width
                spacing: 12
                WifiPanel {
                    objectName: "wifi-panel"; theme: center; Layout.fillWidth: true; visible: center.wifiDetails
                    snapshot: center.snapshot; busy: center.busy; busyAction: center.busyAction; error: center.error
                    onBackRequested: center.wifiDetails = false
                    onControlRequested: (action, value) => center.controlRequested(action, value)
                    onDeviceRequested: device => center.wifiDeviceRequested(device)
                    onSelectedChanged: if (selected) Qt.callLater(center.scrollToTop)
                }
                BluetoothPanel {
                    objectName: "bluetooth-panel"; theme: center; Layout.fillWidth: true; visible: center.bluetoothDetails
                    snapshot: center.snapshot; ready: center.bluetoothReady; busy: center.bluetoothBusy
                    operation: center.bluetoothOperation; error: center.bluetoothError; prompt: center.bluetoothPrompt
                    onBackRequested: center.bluetoothDetails = false
                    onControlRequested: (action, value) => center.bluetoothRequested(action, value)
                    onSelectedIdChanged: if (selectedId) Qt.callLater(center.scrollToTop)
                    onPromptChanged: if (prompt) Qt.callLater(center.scrollToTop)
                }
                ProtonPanel {
                    objectName: "vpn-panel"; theme: center; Layout.fillWidth: true; visible: center.vpnDetails
                    snapshot: center.snapshot; busy: center.vpnBusy; operation: center.vpnOperation; error: center.vpnError
                    onBackRequested: center.vpnDetails = false
                    onControlRequested: (action, value) => center.vpnRequested(action, value)
                    onSigninRequested: center.launchRequested("proton-signin")
                    onRefreshRequested: center.vpnRefreshRequested()
                }
                ColumnLayout {
                    Layout.fillWidth: true; visible: !center.wifiDetails && !center.bluetoothDetails && !center.vpnDetails; spacing: 12
                    GridLayout {
                        Layout.fillWidth: true; columns: 2; rowSpacing: 8; columnSpacing: 8
                        QuickTile {
                            objectName: "wifi"; theme: center; symbol: "wifi"; text: "Wi-Fi"; Layout.fillWidth: true
                            selected: center.snapshot.wifiEnabled === true && available
                            available: center.snapshot.wifiAvailable === true
                            subtitle: !available ? "No adapter" : selected ? center.snapshot.wifiName || "Not connected" : "Off"
                            hasDetails: true; enabled: !center.busy
                            onClicked: if (available) center.controlRequested("wifi-power", {device: center.snapshot.wifiDevice, enabled: !selected})
                            onDetailsRequested: center.openWifi()
                        }
                        QuickTile {
                            objectName: "bluetooth"; theme: center; symbol: "bluetooth"; text: "Bluetooth"; Layout.fillWidth: true
                            selected: center.snapshot.bluetoothEnabled === true && available
                            available: center.snapshot.bluetoothAvailable === true
                            subtitle: !available ? "No adapter" : selected ? "On" : "Off"
                            hasDetails: true; enabled: !center.busy && !center.bluetoothBusy
                            onClicked: if (available && center.bluetoothReady) center.controlRequested("bluetooth", !selected)
                            onDetailsRequested: center.openBluetooth()
                        }
                        QuickTile {
                            objectName: "mic"; theme: center; symbol: "mic"; text: "Microphone"; Layout.fillWidth: true
                            available: !!center.input; selected: available && !center.input.muted
                            subtitle: !available ? "No input" : selected ? "Enabled" : "Muted"
                            hasDetails: true; enabled: !center.busy
                            onClicked: if (available) center.controlRequested("mic", selected)
                            onDetailsRequested: center.audioDetails = !center.audioDetails
                        }
                        QuickTile {
                            objectName: "night"; theme: center; symbol: "suspend"; text: "Night light"; Layout.fillWidth: true
                            available: center.snapshot.nightAvailable === true; selected: center.nightEnabled
                            subtitle: !available ? "Needs hyprsunset" : selected ? "Warm · 4000 K" : "Off"
                            onClicked: if (available) center.nightRequested()
                        }
                        QuickTile {
                            objectName: "vpn"; theme: center; symbol: "vpn"; text: "VPN"; Layout.fillWidth: true
                            available: center.snapshot.vpnReady === true; selected: center.snapshot.vpnConnected === true
                            subtitle: center.vpnBusy ? center.vpnOperation === "disconnect" ? "Disconnecting…" : "Connecting…"
                                : selected ? center.snapshot.vpnServer || "Proton VPN" : available ? "Off · Proton VPN"
                                : ({signin: "Sign in · Proton VPN", install: "Install Proton VPN", network: "Setup Proton VPN", unknown: "Status unavailable"}[center.snapshot.vpnStatus] || "Checking Proton VPN…")
                            hasDetails: true; enabled: !center.busy && !center.vpnBusy
                            onClicked: { if (available) center.vpnRequested(selected ? "disconnect" : "connect", selected ? null : ""); else center.openVpn(); }
                            onDetailsRequested: center.openVpn()
                        }
                        QuickTile {
                            objectName: "color"; theme: center; symbol: "color"; text: "Color picker"; Layout.fillWidth: true
                            subtitle: "Pick and copy"
                            onClicked: center.launchRequested("color")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        IconButton {
                            objectName: "audio-mute"; symbol: center.output?.muted ? "muted" : "volume"
                            enabled: !!center.output && !center.busy; Accessible.name: center.output?.muted ? "Unmute audio" : "Mute audio"
                            onClicked: center.controlRequested("mute", !center.output.muted)
                        }
                        Slider {
                            id: volume
                            objectName: "volume"; Layout.fillWidth: true; from: 0; to: 100; stepSize: 1
                            enabled: !!center.output && !center.busy
                            value: center.output?.volume || 0
                            Accessible.name: "Volume"
                            palette.highlight: center.accent; palette.button: center.accent; palette.dark: center.raised
                            background: Rectangle {
                                x: volume.leftPadding; y: volume.topPadding + volume.availableHeight / 2 - height / 2
                                width: volume.availableWidth; height: 6; radius: 3; color: center.raised
                                Rectangle { width: volume.visualPosition * parent.width; height: parent.height; radius: 3; color: center.accent }
                            }
                            handle: Rectangle {
                                x: volume.leftPadding + volume.visualPosition * (volume.availableWidth - width)
                                y: volume.topPadding + volume.availableHeight / 2 - height / 2
                                width: 20; height: 20; radius: 10; color: center.accent
                                border.width: volume.visualFocus ? 3 : 0; border.color: center.textColor
                            }
                            // Commit once on release; keyboard changes are immediate.
                            onMoved: if (!pressed) center.controlRequested("volume", value)
                            onPressedChanged: if (!pressed) center.controlRequested("volume", value)
                        }
                        Text { text: Math.round(volume.value) + "%"; font.family: center.uiFont; font.pixelSize: 12; color: center.textColor; Layout.preferredWidth: 35 }
                    }
                    SettingsComboBox {
                        objectName: "audio-output"; theme: center; Layout.fillWidth: true
                        model: center.snapshot.outputs || []; currentIndex: (center.snapshot.outputs || []).findIndex(item => item.id === center.snapshot.output)
                        displayText: center.output?.name || "No audio output"; enabled: !!center.output && !center.busy
                        Accessible.name: "Audio output"
                        onActivated: center.controlRequested("output", currentValue)
                    }
                    SettingsComboBox {
                        objectName: "audio-input"; theme: center; Layout.fillWidth: true; visible: center.audioDetails
                        model: center.snapshot.inputs || []; currentIndex: (center.snapshot.inputs || []).findIndex(item => item.id === center.snapshot.input)
                        displayText: center.input?.name || "No microphone input"; enabled: !!center.input && !center.busy
                        Accessible.name: "Microphone input"
                        onActivated: center.controlRequested("input", currentValue)
                    }
                    SettingsButton { theme: center; text: "Audio mixer"; visible: center.audioDetails; onClicked: center.launchRequested("audio") }
                    Text {
                        text: center.error || (center.busy ? "Applying…" : ""); visible: text !== ""; textFormat: Text.PlainText
                        font.family: center.uiFont; font.pixelSize: 12; color: center.accent; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: center.raised }
        // 3. Notifications use the remaining height.
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Text { text: "Notifications" + (center.notifications.length ? " · " + center.notifications.length : ""); font.family: center.uiFont; font.pixelSize: 16; font.weight: Font.DemiBold; color: center.textColor; Layout.fillWidth: true }
            SettingsButton { objectName: "dnd"; theme: center; text: "DND"; primary: center.dnd; Accessible.name: "Do not disturb"; onClicked: center.dndRequested() }
            SettingsButton { objectName: "clear"; theme: center; text: "Clear"; enabled: center.notifications.length > 0; Accessible.name: "Clear notifications"; onClicked: center.clearRequested() }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 64
            ColumnLayout {
                visible: center.notifications.length === 0; anchors.centerIn: parent; spacing: 10
                SessionIcon { name: "bell"; color: center.textColor; opacity: 0.35; Layout.alignment: Qt.AlignHCenter; implicitWidth: 32; implicitHeight: 32 }
                Text { text: "You're all caught up"; font.family: center.uiFont; font.pixelSize: 14; color: center.textColor; opacity: 0.6 }
            }
            ListView {
                id: notificationList
                objectName: "notifications"; anchors.fill: parent; clip: true; spacing: 8
                model: center.notifications
                ScrollBar.vertical: ScrollBar {}
                delegate: NotificationCard {
                    required property var modelData
                    width: notificationList.width; theme: center; notification: modelData
                }
            }
        }
    }
}
