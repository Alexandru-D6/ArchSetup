pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: wifi
    required property var theme
    property var snapshot: ({})
    property bool busy: false
    property string busyAction: ""
    property string error: ""
    property var selected: null
    readonly property var networks: snapshot.wifiNetworks || []
    readonly property bool powered: snapshot.wifiEnabled === true
    readonly property bool connected: selected !== null && networks.some(item => item.ssid === selected.ssid && item.security === selected.security && item.connected)
    readonly property bool needsPassword: selected !== null && selected.security === "psk" && !connected
    signal backRequested()
    signal controlRequested(string action, var value)
    signal deviceRequested(string device)
    spacing: 10
    onVisibleChanged: { selected = null; password.clear(); }
    onSelectedChanged: password.clear()
    function request(action, extra) {
        controlRequested(action, Object.assign({device: snapshot.wifiDevice}, extra || {}));
    }
    function submit() {
        if (busy || !selected || !powered || !connectButton.enabled) return;
        if (connected) request("wifi-disconnect");
        else request("wifi-connect", {ssid: selected.ssid, security: selected.security, passphrase: password.text});
        password.clear();
    }
    RowLayout {
        Layout.fillWidth: true
        SettingsButton { objectName: "wifi-back"; theme: wifi.theme; text: "Back"; Accessible.name: "Back to quick actions"; onClicked: wifi.backRequested() }
        Text { text: "Wi-Fi"; font.family: wifi.theme.uiFont; font.pixelSize: 17; font.weight: Font.DemiBold; color: wifi.theme.textColor; Layout.fillWidth: true }
        SettingsButton {
            objectName: "wifi-power"; theme: wifi.theme; text: wifi.powered ? "Turn off" : "Turn on"
            enabled: wifi.snapshot.wifiAvailable === true && !wifi.busy
            onClicked: wifi.request("wifi-power", {enabled: !wifi.powered})
        }
    }
    SettingsComboBox {
        objectName: "wifi-device"; theme: wifi.theme; Layout.fillWidth: true
        model: wifi.snapshot.wifiDevices || []; visible: count > 1; enabled: !wifi.busy
        currentIndex: (wifi.snapshot.wifiDevices || []).findIndex(item => item.id === wifi.snapshot.wifiDevice)
        Accessible.name: "Wi-Fi adapter"
        onActivated: { wifi.selected = null; wifi.deviceRequested(currentValue); }
    }
    Text {
        objectName: "wifi-status"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: !wifi.snapshot.wifiAvailable ? "Wi-Fi unavailable" : !wifi.powered ? "Wi-Fi is off"
            : wifi.busyAction === "wifi-connect" && wifi.busy ? "Connecting…"
            : wifi.snapshot.wifiState === "connecting" ? "Connecting…"
            : wifi.snapshot.wifiName ? "Connected to " + wifi.snapshot.wifiName : "Not connected"
        font.family: wifi.theme.uiFont; font.pixelSize: 13; color: wifi.theme.textColor
    }
    Text {
        objectName: "wifi-error"; text: wifi.error || wifi.snapshot.wifiError || ""; visible: text !== ""
        textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
        font.family: wifi.theme.uiFont; font.pixelSize: 12; color: wifi.theme.accent
    }
    ColumnLayout {
        visible: wifi.selected !== null && wifi.powered; Layout.fillWidth: true; spacing: 8
        Text {
            text: wifi.selected?.ssid || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
            font.family: wifi.theme.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold; color: wifi.theme.textColor
        }
        SettingsField {
            id: password
            objectName: "wifi-password"; theme: wifi.theme; Layout.fillWidth: true
            visible: wifi.needsPassword; enabled: !wifi.busy; echoMode: TextInput.Password
            maximumLength: 63; inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            placeholderText: wifi.selected?.known ? "Saved password · leave blank to reuse" : "Wi-Fi password"
            Accessible.name: "Wi-Fi password"; onAccepted: wifi.submit()
        }
        Text {
            visible: wifi.selected?.security === "8021x" && !wifi.selected?.known
            text: "Enterprise networks need an existing iwd configuration."
            font.family: wifi.theme.uiFont; font.pixelSize: 12; color: wifi.theme.textColor
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        SettingsButton {
            id: connectButton
            objectName: "wifi-connect"; theme: wifi.theme; primary: true; Layout.fillWidth: true
            text: wifi.connected ? "Disconnect" : "Connect"
            enabled: !wifi.busy && wifi.powered && wifi.selected !== null
                && wifi.selected.security !== "wep"
                && (wifi.selected.security !== "8021x" || wifi.selected.known)
                && (!wifi.needsPassword || password.length >= 8 || (wifi.selected.known && password.length === 0))
            onClicked: wifi.submit()
        }
    }
    RowLayout {
        visible: wifi.powered; Layout.fillWidth: true
        Text {
            text: "Available networks"; font.family: wifi.theme.uiFont; font.pixelSize: 13
            color: wifi.theme.textColor; Layout.fillWidth: true
        }
        SettingsButton {
            objectName: "wifi-scan"; theme: wifi.theme
            text: wifi.snapshot.wifiScanning || (wifi.busy && wifi.busyAction === "wifi-scan") ? "Scanning…" : "Scan"
            enabled: !wifi.busy && !wifi.snapshot.wifiScanning
            onClicked: wifi.request("wifi-scan")
        }
    }
    Text {
        visible: wifi.powered && wifi.networks.length === 0
        text: wifi.snapshot.wifiScanning ? "Looking for networks…" : "No networks found. Try scanning again."
        font.family: wifi.theme.uiFont; font.pixelSize: 12; color: wifi.theme.textColor
        wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    Repeater {
        model: wifi.powered ? wifi.networks : []
        delegate: Button {
            id: network
            required property var modelData
            objectName: "wifi-network-" + modelData.ssid
            Layout.fillWidth: true; implicitHeight: 62; padding: 12
            enabled: !wifi.busy
            Accessible.name: modelData.ssid + (modelData.connected ? ", connected" : ", " + modelData.security)
            onClicked: wifi.selected = modelData
            background: Rectangle {
                radius: 14; color: wifi.theme.raised
                border.width: network.hovered || network.activeFocus || (wifi.selected?.ssid === network.modelData.ssid && wifi.selected?.security === network.modelData.security) ? 2 : 0
                border.color: wifi.theme.accent
            }
            contentItem: RowLayout {
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4
                    Text {
                        text: network.modelData.ssid; textFormat: Text.PlainText; elide: Text.ElideRight
                        Layout.fillWidth: true; font.family: wifi.theme.uiFont; font.pixelSize: 13; color: wifi.theme.textColor
                    }
                    Text {
                        text: (network.modelData.connected ? "Connected · " : network.modelData.known ? "Saved · " : "")
                            + (network.modelData.security === "open" ? "Open" : network.modelData.security === "psk" ? "Password protected" : network.modelData.security === "wep" ? "Unsupported security" : "Enterprise")
                        Layout.fillWidth: true; elide: Text.ElideRight
                        font.family: wifi.theme.uiFont; font.pixelSize: 11; color: wifi.theme.textColor; opacity: 0.7
                    }
                }
                Text {
                    text: network.modelData.signal + "/4"; Accessible.name: "Signal strength " + text
                    font.family: wifi.theme.uiFont; font.pixelSize: 12; color: wifi.theme.textColor
                }
            }
        }
    }
}
