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
    readonly property string providerId: snapshot.vpnProvider || "proton"
    readonly property string providerName: snapshot.vpnProviderName || "Proton VPN"
    readonly property var providers: snapshot.vpnProviders || [{id: providerId, name: providerName}]
    readonly property bool tailnet: snapshot.vpnLocationKind === "exit-node"
    readonly property bool connected: snapshot.vpnConnected === true
    readonly property bool ready: snapshot.vpnReady === true
    signal backRequested()
    signal providerRequested(string provider)
    signal controlRequested(string action, var value)
    signal signinRequested()
    signal refreshRequested()
    spacing: 12
    function resetLocation() {
        if (!location) return;
        const selected = (snapshot.vpnLocations || []).find(item => item.id === snapshot.vpnLocation);
        location.text = snapshot.vpnLocationKind === "exit-node" && selected ? selected.name : "";
    }
    onProviderIdChanged: resetLocation()
    Component.onCompleted: resetLocation()
    RowLayout {
        Layout.fillWidth: true
        SettingsButton { objectName: "vpn-back"; theme: vpn.theme; text: "Back"; Accessible.name: "Back to quick actions"; onClicked: vpn.backRequested() }
        Text { text: "VPN"; font.family: vpn.theme.uiFont; font.pixelSize: 17; font.weight: Font.DemiBold; color: vpn.theme.textColor; Layout.fillWidth: true }
        SettingsButton { objectName: "vpn-refresh"; theme: vpn.theme; text: "Refresh"; enabled: !vpn.busy; onClicked: vpn.refreshRequested() }
    }
    SettingsComboBox {
        objectName: "vpn-provider"; theme: vpn.theme; Layout.fillWidth: true
        model: vpn.providers
        currentIndex: vpn.providers.findIndex(item => item.id === vpn.providerId)
        enabled: !vpn.busy
        Accessible.name: "VPN provider"
        onActivated: vpn.providerRequested(currentValue)
    }
    Text {
        objectName: "vpn-status"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: vpn.busy ? ({disconnect: "Disconnecting…", "select-provider": "Switching provider…", "set-location": "Updating exit node…"}[vpn.operation] || "Connecting…")
            : ({connected: "Connected", disconnected: "Disconnected", signin: "Sign in to " + vpn.providerName,
                install: vpn.providerName + " is not installed", network: "VPN setup required", service: "Start the VPN service",
                approval: "Device approval required", connecting: "Connecting…", unknown: "Status unavailable"}[vpn.snapshot.vpnStatus] || "Checking " + vpn.providerName + "…")
        font.family: vpn.theme.uiFont; font.pixelSize: 15; color: vpn.connected ? vpn.theme.accent : vpn.theme.textColor
    }
    Text {
        objectName: "vpn-server"; visible: vpn.connected; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: (vpn.snapshot.vpnServer || "") + (vpn.snapshot.vpnProtocol ? " · " + vpn.snapshot.vpnProtocol : "")
        font.family: vpn.theme.uiFont; font.pixelSize: 13; color: vpn.theme.textColor
    }
    Text {
        objectName: "vpn-address"; visible: vpn.connected && text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: [vpn.snapshot.vpnNetwork || "", vpn.snapshot.vpnAddress || ""].filter(value => value !== "").join(" · ")
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.textColor
    }
    Text {
        objectName: "vpn-error"; text: vpn.error || vpn.snapshot.vpnError || ""; visible: text !== ""
        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.accent
    }
    SettingsSearchBox {
        id: location
        objectName: vpn.tailnet ? "vpn-exit-node" : "vpn-country"
        theme: vpn.theme; Layout.fillWidth: true
        visible: vpn.ready && (!vpn.connected || vpn.tailnet); enabled: !vpn.busy
        options: [{id: "", name: vpn.tailnet ? "Tailnet only (no exit node)" : "Fastest available"}]
            .concat(vpn.snapshot.vpnLocations || vpn.snapshot.vpnCountries || [])
        placeholderText: vpn.tailnet ? "Tailnet only (no exit node)" : "Fastest available"
        maximumLength: vpn.tailnet ? 253 : 64
        accessibleName: vpn.tailnet ? "Choose a Tailscale exit node, or leave empty for tailnet access only"
            : "Search VPN countries by name or code; leave empty for the fastest server"
    }
    Text {
        objectName: "vpn-countries-error"
        text: vpn.snapshot.vpnLocationsError || vpn.snapshot.vpnCountriesError || ""
        visible: location.visible && text !== ""
        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.accent
    }
    Text {
        visible: location.visible; Layout.fillWidth: true; wrapMode: Text.Wrap
        text: vpn.snapshot.vpnLocationHint || (vpn.tailnet ? "An exit node routes internet traffic through that device. Without one, Tailscale connects your tailnet devices only."
            : "Type to filter countries, or leave blank for the fastest server. Choosing a country requires a paid Proton plan.")
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.textColor; opacity: 0.7
    }
    SettingsButton {
        objectName: "vpn-apply-location"; theme: vpn.theme; Layout.fillWidth: true
        visible: vpn.tailnet && vpn.connected
        enabled: !vpn.busy && location.valid && location.value !== (vpn.snapshot.vpnLocation || "")
        text: location.value ? "Apply exit node" : "Use tailnet only"
        onClicked: vpn.controlRequested("set-location", location.value)
    }
    SettingsButton {
        objectName: "vpn-connect"; theme: vpn.theme; Layout.fillWidth: true; primary: true
        visible: vpn.ready; enabled: vpn.ready && !vpn.busy && (vpn.connected || location.valid)
        text: vpn.connected ? "Disconnect" : vpn.tailnet
            ? location.valid ? location.value ? "Connect with exit node" : "Connect to " + vpn.providerName : "Choose an exit node"
            : location.value ? "Connect to country" : location.valid ? "Connect to fastest server" : "Choose a country"
        onClicked: vpn.controlRequested(vpn.connected ? "disconnect" : "connect", vpn.connected ? null : location.value)
    }
    SettingsButton {
        objectName: "vpn-signin"; theme: vpn.theme; Layout.fillWidth: true
        visible: vpn.snapshot.vpnStatus === "signin"; enabled: !vpn.busy; text: "Sign in"
        onClicked: vpn.signinRequested()
    }
    Text {
        visible: vpn.snapshot.vpnStatus === "signin"; Layout.fillWidth: true; wrapMode: Text.Wrap
        text: vpn.snapshot.vpnSigninHint || (vpn.tailnet ? "Sign in opens Tailscale’s browser authorization flow in a terminal."
            : "Sign in opens Proton’s terminal prompt for your password and two-factor authentication.")
        font.family: vpn.theme.uiFont; font.pixelSize: 12; color: vpn.theme.textColor; opacity: 0.7
    }
    SettingsButton {
        objectName: "vpn-setup"; theme: vpn.theme; text: vpn.providerName + " setup guide"; Layout.fillWidth: true
        visible: ["install", "network", "service", "approval"].includes(vpn.snapshot.vpnStatus)
        onClicked: Qt.openUrlExternally(vpn.snapshot.vpnSetupUrl || "https://protonvpn.com/support/linux-vpn-arch")
    }
}
