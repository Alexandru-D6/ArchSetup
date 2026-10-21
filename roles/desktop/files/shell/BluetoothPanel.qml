pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: bluetooth
    required property var theme
    property var snapshot: ({})
    property bool ready: false
    property bool busy: false
    property string operation: ""
    property string error: ""
    property var prompt: null
    property string selectedId: ""
    property bool confirmingForget: false
    readonly property var devices: snapshot.bluetoothDevices || []
    readonly property var device: devices.find(item => item.id === selectedId) || null
    readonly property bool powered: snapshot.bluetoothEnabled === true
    readonly property bool enteringCode: prompt?.kind === "pin" || prompt?.kind === "passkey"
    signal backRequested()
    signal controlRequested(string action, var value)
    spacing: 10
    onVisibleChanged: { selectedId = ""; confirmingForget = false; code.clear(); }
    onSelectedIdChanged: { confirmingForget = false; code.clear(); }
    onPromptChanged: code.clear()
    function respond(value) { controlRequested("respond", value); code.clear(); }
    RowLayout {
        Layout.fillWidth: true
        SettingsButton { objectName: "bluetooth-back"; theme: bluetooth.theme; text: "Back"; Accessible.name: "Back to quick actions"; onClicked: bluetooth.backRequested() }
        Text { text: "Bluetooth"; font.family: bluetooth.theme.uiFont; font.pixelSize: 17; font.weight: Font.DemiBold; color: bluetooth.theme.textColor; Layout.fillWidth: true }
        SettingsButton {
            objectName: "bluetooth-power"; theme: bluetooth.theme; text: bluetooth.powered ? "Turn off" : "Turn on"
            enabled: bluetooth.ready && bluetooth.snapshot.bluetoothAvailable === true && !bluetooth.busy
            onClicked: bluetooth.controlRequested("power", !bluetooth.powered)
        }
    }
    SettingsComboBox {
        objectName: "bluetooth-adapter"; theme: bluetooth.theme; Layout.fillWidth: true
        model: bluetooth.snapshot.bluetoothAdapters || []; visible: count > 1; enabled: bluetooth.ready && !bluetooth.busy
        currentIndex: (bluetooth.snapshot.bluetoothAdapters || []).findIndex(item => item.id === bluetooth.snapshot.bluetoothAdapter)
        Accessible.name: "Bluetooth adapter"
        onActivated: { bluetooth.selectedId = ""; bluetooth.controlRequested("select", currentValue); }
    }
    Text {
        objectName: "bluetooth-status"; Layout.fillWidth: true; wrapMode: Text.Wrap
        text: !bluetooth.ready ? bluetooth.error ? "Bluetooth unavailable" : "Loading Bluetooth…" : !bluetooth.snapshot.bluetoothAvailable ? "Bluetooth unavailable"
            : !bluetooth.powered ? "Bluetooth is off" : bluetooth.busy ? ({pair: "Pairing…", connect: "Connecting…", disconnect: "Disconnecting…", forget: "Forgetting device…"}[bluetooth.operation] || "Applying…")
            : bluetooth.devices.some(item => item.connected) ? bluetooth.devices.filter(item => item.connected).length + " device(s) connected"
            : "No devices connected"
        font.family: bluetooth.theme.uiFont; font.pixelSize: 13; color: bluetooth.theme.textColor
    }
    Text {
        objectName: "bluetooth-error"; text: bluetooth.error || bluetooth.snapshot.bluetoothError || ""; visible: text !== ""
        textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
        font.family: bluetooth.theme.uiFont; font.pixelSize: 12; color: bluetooth.theme.accent
    }
    ColumnLayout {
        visible: bluetooth.prompt !== null; Layout.fillWidth: true; spacing: 8
        Text {
            objectName: "bluetooth-prompt"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: !bluetooth.prompt ? "" : bluetooth.prompt.kind === "confirm" ? "Does this code match the one on " + bluetooth.prompt.name + "?"
                : bluetooth.prompt.kind === "authorize" ? "Allow pairing with " + bluetooth.prompt.name + "?"
                : bluetooth.prompt.kind === "display" ? "Type this code on " + bluetooth.prompt.name + ", then press Enter."
                : "Enter the " + (bluetooth.prompt.kind === "pin" ? "PIN" : "passkey") + " shown on " + bluetooth.prompt.name + "."
            font.family: bluetooth.theme.uiFont; font.pixelSize: 13; color: bluetooth.theme.textColor
        }
        Text {
            objectName: "bluetooth-pairing-code"; text: bluetooth.prompt?.code || ""; visible: text !== ""
            textFormat: Text.PlainText; font.family: bluetooth.theme.uiFont; font.pixelSize: 26; font.letterSpacing: 3
            color: bluetooth.theme.accent; Layout.alignment: Qt.AlignHCenter
        }
        SettingsField {
            id: code
            objectName: "bluetooth-code"; theme: bluetooth.theme; Layout.fillWidth: true
            visible: bluetooth.enteringCode; maximumLength: bluetooth.prompt?.kind === "passkey" ? 6 : 16
            placeholderText: bluetooth.prompt?.kind === "passkey" ? "Passkey" : "PIN"
            echoMode: TextInput.Password; inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            Accessible.name: placeholderText
            onAccepted: if (submitCode.enabled) bluetooth.respond(text)
        }
        RowLayout {
            Layout.fillWidth: true; visible: bluetooth.prompt?.kind !== "display"
            SettingsButton {
                objectName: "bluetooth-reject"; theme: bluetooth.theme; text: "Cancel"; Layout.fillWidth: true
                onClicked: bluetooth.controlRequested("cancel", null)
            }
            SettingsButton {
                id: submitCode
                objectName: "bluetooth-confirm"; theme: bluetooth.theme; primary: true; Layout.fillWidth: true
                text: bluetooth.enteringCode ? "Submit" : "Confirm"
                enabled: !bluetooth.enteringCode || (code.length > 0 && (bluetooth.prompt?.kind !== "passkey" || /^[0-9]{1,6}$/.test(code.text)))
                onClicked: bluetooth.respond(bluetooth.enteringCode ? code.text : true)
            }
        }
    }
    SettingsButton {
        objectName: "bluetooth-cancel"; theme: bluetooth.theme; text: "Cancel"; Layout.fillWidth: true
        visible: bluetooth.busy && ["pair", "connect"].includes(bluetooth.operation) && (!bluetooth.prompt || bluetooth.prompt.kind === "display")
        onClicked: bluetooth.controlRequested("cancel", null)
    }
    ColumnLayout {
        visible: bluetooth.device !== null && !bluetooth.prompt; Layout.fillWidth: true; spacing: 8
        Text {
            text: bluetooth.device?.name || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
            font.family: bluetooth.theme.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold; color: bluetooth.theme.textColor
        }
        Text {
            text: bluetooth.device?.address || ""; font.family: bluetooth.theme.uiFont; font.pixelSize: 11; color: bluetooth.theme.textColor; opacity: 0.7
        }
        SettingsButton {
            objectName: "bluetooth-connect"; theme: bluetooth.theme; primary: true; Layout.fillWidth: true
            text: bluetooth.device?.connected ? "Disconnect" : bluetooth.device?.paired ? "Connect" : "Pair and connect"
            enabled: bluetooth.ready && !bluetooth.busy && bluetooth.powered && bluetooth.device !== null
            onClicked: bluetooth.controlRequested(bluetooth.device.connected ? "disconnect" : bluetooth.device.paired ? "connect" : "pair", bluetooth.device.id)
        }
        SettingsButton {
            objectName: "bluetooth-forget"; theme: bluetooth.theme; text: "Forget device"; Layout.fillWidth: true
            visible: (bluetooth.device?.paired || bluetooth.device?.trusted || false) && !bluetooth.confirmingForget
            enabled: bluetooth.ready && !bluetooth.busy
            onClicked: bluetooth.confirmingForget = true
        }
        Text {
            visible: bluetooth.confirmingForget; text: "Forget this device? You will need to pair it again."
            wrapMode: Text.Wrap; Layout.fillWidth: true; font.family: bluetooth.theme.uiFont; font.pixelSize: 12; color: bluetooth.theme.textColor
        }
        RowLayout {
            visible: bluetooth.confirmingForget; Layout.fillWidth: true
            SettingsButton { objectName: "bluetooth-forget-cancel"; theme: bluetooth.theme; text: "Keep"; Layout.fillWidth: true; onClicked: bluetooth.confirmingForget = false }
            SettingsButton {
                objectName: "bluetooth-forget-confirm"; theme: bluetooth.theme; text: "Forget"; Layout.fillWidth: true
                enabled: bluetooth.ready && !bluetooth.busy
                onClicked: { bluetooth.controlRequested("forget", bluetooth.device.id); bluetooth.confirmingForget = false; }
            }
        }
    }
    RowLayout {
        visible: bluetooth.powered; Layout.fillWidth: true
        Text { text: "Devices"; font.family: bluetooth.theme.uiFont; font.pixelSize: 13; color: bluetooth.theme.textColor; Layout.fillWidth: true }
        SettingsButton {
            objectName: "bluetooth-scan"; theme: bluetooth.theme; text: bluetooth.snapshot.bluetoothScanning ? "Stop scan" : "Scan"
            enabled: bluetooth.ready && !bluetooth.busy
            onClicked: bluetooth.controlRequested("scan", !bluetooth.snapshot.bluetoothScanning)
        }
    }
    Text {
        visible: bluetooth.powered && bluetooth.devices.length === 0
        text: bluetooth.snapshot.bluetoothScanning ? "Looking for devices… Put your device in pairing mode." : "No devices found. Put your device in pairing mode, then scan."
        font.family: bluetooth.theme.uiFont; font.pixelSize: 12; color: bluetooth.theme.textColor
        wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    Repeater {
        model: bluetooth.devices
        delegate: Button {
            id: deviceButton
            required property var modelData
            objectName: "bluetooth-device-" + modelData.address
            Layout.fillWidth: true; implicitHeight: 62; padding: 12
            enabled: bluetooth.ready && !bluetooth.busy
            Accessible.name: modelData.name + (modelData.connected ? ", connected" : modelData.paired ? ", paired" : ", available")
            onClicked: bluetooth.selectedId = modelData.id
            background: Rectangle {
                radius: 14; color: bluetooth.theme.raised
                border.width: deviceButton.hovered || deviceButton.activeFocus || bluetooth.selectedId === deviceButton.modelData.id ? 2 : 0
                border.color: bluetooth.theme.accent
            }
            contentItem: RowLayout {
                SessionIcon { name: "bluetooth"; color: bluetooth.theme.textColor; implicitWidth: 20; implicitHeight: 20 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4
                    Text {
                        text: deviceButton.modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight
                        Layout.fillWidth: true; font.family: bluetooth.theme.uiFont; font.pixelSize: 13; color: bluetooth.theme.textColor
                    }
                    Text {
                        text: (deviceButton.modelData.connected ? "Connected" : deviceButton.modelData.paired ? "Paired" : "Available")
                            + (deviceButton.modelData.battery >= 0 ? " · " + deviceButton.modelData.battery + "% battery" : "")
                        Layout.fillWidth: true; elide: Text.ElideRight
                        font.family: bluetooth.theme.uiFont; font.pixelSize: 11; color: bluetooth.theme.textColor; opacity: 0.7
                    }
                }
            }
        }
    }
}
