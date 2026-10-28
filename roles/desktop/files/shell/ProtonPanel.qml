pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: vpn
    required property var theme
    property var snapshot: ({})
    property bool busy: false
    property string operation: ""
    property string error: ""
    readonly property bool connected: snapshot.vpnConnected === true
    readonly property bool ready: snapshot.vpnReady === true
    signal backRequested()
    signal controlRequested(string action, var value)
    signal signinRequested()
    signal refreshRequested()
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        SettingsButton { objectName: "vpn-back"; theme: vpn.theme; text: "Back"; Accessible.name: "Back to quick actions"; onClicked: vpn.backRequested() }
        Text { text: "Proton VPN"; font.family: vpn.theme.uiFont; font.pixelSize: 17; font.weight: Font.DemiBold; color: vpn.theme.textColor; Layout.fillWidth: true }
        SettingsButton { objectName: "vpn-refresh"; theme: vpn.theme; text: "Refresh"; enabled: !vpn.busy; onClicked: vpn.refreshRequested() }
    }
    Text {
        objectName: "vpn-status"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: vpn.busy ? vpn.operation === "disconnect" ? "Disconnecting…" : "Connecting…"
            : ({connected: "Connected", disconnected: "Disconnected", signin: "Sign in to Proton VPN", install: "Proton VPN is not installed", network: "VPN setup required", unknown: "Status unavailable"}[vpn.snapshot.vpnStatus] || "Checking Proton VPN…")
        font.family: vpn.theme.uiFont; font.pixelSize: 15; color: vpn.connected ? vpn.theme.accent : vpn.theme.textColor
    }
    Text {
        objectName: "vpn-server"; visible: vpn.connected; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: (vpn.snapshot.vpnServer || "") + (vpn.snapshot.vpnProtocol ? " · " + vpn.snapshot.vpnProtocol : "")
        font.family: vpn.theme.uiFont; font.pixelSize: 13; color: vpn.theme.textColor
    }
    Text {
        objectName: "vpn-error"; text: vpn.error || vpn.snapshot.vpnError || ""; visible: text !== ""
        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.accent
    }
    SettingsField {
        id: country
        objectName: "vpn-country"; theme: vpn.theme; Layout.fillWidth: true
        visible: vpn.ready && !vpn.connected; enabled: !vpn.busy
        placeholderText: "Country (optional), e.g. ES"; maximumLength: 64
        Accessible.name: "VPN country; leave empty for the fastest server"
        onAccepted: if (connect.enabled) vpn.controlRequested("connect", text.trim())
    }
    Text {
        visible: vpn.ready && !vpn.connected; Layout.fillWidth: true; wrapMode: Text.Wrap
        text: "Leave the country blank for the fastest server. Choosing a country requires a paid Proton plan."
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.textColor; opacity: 0.7
    }
    SettingsButton {
        id: connect
        objectName: "vpn-connect"; theme: vpn.theme; Layout.fillWidth: true; primary: true
        visible: vpn.ready; enabled: vpn.ready && !vpn.busy && (vpn.connected || country.text.trim() === "" || /^[A-Za-z][A-Za-z -]{0,63}$/.test(country.text.trim()))
        text: vpn.connected ? "Disconnect" : country.text.trim() ? "Connect to country" : "Connect to fastest server"
        onClicked: vpn.controlRequested(vpn.connected ? "disconnect" : "connect", vpn.connected ? null : country.text.trim())
    }
    SettingsButton {
        objectName: "vpn-signin"; theme: vpn.theme; Layout.fillWidth: true
        visible: vpn.snapshot.vpnStatus === "signin"; enabled: !vpn.busy; text: "Sign in"
        onClicked: vpn.signinRequested()
    }
    Text {
        visible: vpn.snapshot.vpnStatus === "signin"; Layout.fillWidth: true; wrapMode: Text.Wrap
        text: "Sign in opens Proton’s terminal prompt for your password and two-factor authentication."
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.textColor; opacity: 0.7
    }
    SettingsButton {
        objectName: "vpn-setup"; theme: vpn.theme; text: "Proton VPN setup guide"; Layout.fillWidth: true
        visible: ["install", "network"].includes(vpn.snapshot.vpnStatus)
        onClicked: Qt.openUrlExternally("https://protonvpn.com/support/linux-vpn-arch")
    }
}
