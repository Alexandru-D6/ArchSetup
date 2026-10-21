import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Item {
    width: 420; height: 900
    ControlCenter { id: testTheme; visible: false }
    WifiPanel { id: wifi; theme: testTheme; width: 380; anchors.centerIn: parent }
    SignalSpy { id: control; target: wifi; signalName: "controlRequested" }
    SignalSpy { id: device; target: wifi; signalName: "deviceRequested" }
    TestCase {
        name: "WifiPanel"
        when: windowShown
        function init() {
            wifi.visible = true; wifi.selected = null; wifi.busy = false; wifi.error = ""; wifi.busyAction = "";
            wifi.snapshot = {wifiAvailable: true, wifiEnabled: true, wifiDevice: "wlan0", wifiName: "Home",
                wifiDevices: [{id: "wlan0", name: "wlan0"}, {id: "wlan1", name: "wlan1"}],
                wifiNetworks: [{ssid: "Home", security: "psk", known: true, connected: true, signal: 4},
                    {ssid: "New network", security: "psk", known: false, connected: false, signal: 3},
                    {ssid: "Cafe", security: "open", known: false, connected: false, signal: 2}]};
            control.clear(); device.clear(); wait(20);
        }
        function test_connect_password_disconnect_and_clear_secret() {
            mouseClick(findChild(wifi, "wifi-network-New network"));
            const password = findChild(wifi, "wifi-password");
            verify(password.visible); verify(!findChild(wifi, "wifi-connect").enabled);
            password.text = "test password";
            mouseClick(findChild(wifi, "wifi-connect"));
            compare(Array.from(control.signalArguments[0]), ["wifi-connect", {device: "wlan0", ssid: "New network", security: "psk", passphrase: "test password"}]);
            compare(password.text, "");
            mouseClick(findChild(wifi, "wifi-network-Home"));
            verify(!password.visible); compare(findChild(wifi, "wifi-connect").text, "Disconnect");
            mouseClick(findChild(wifi, "wifi-connect"));
            compare(Array.from(control.signalArguments[1]), ["wifi-disconnect", {device: "wlan0"}]);
        }
        function test_open_and_saved_networks_do_not_require_password() {
            mouseClick(findChild(wifi, "wifi-network-Cafe"));
            verify(!findChild(wifi, "wifi-password").visible);
            mouseClick(findChild(wifi, "wifi-connect"));
            compare(Array.from(control.signalArguments[0]), ["wifi-connect", {device: "wlan0", ssid: "Cafe", security: "open", passphrase: ""}]);
            wifi.selected = {ssid: "Saved", security: "psk", known: true};
            verify(findChild(wifi, "wifi-connect").enabled);
        }
        function test_power_scan_and_adapter_selection() {
            mouseClick(findChild(wifi, "wifi-power"));
            compare(Array.from(control.signalArguments[0]), ["wifi-power", {device: "wlan0", enabled: false}]);
            mouseClick(findChild(wifi, "wifi-scan"));
            compare(Array.from(control.signalArguments[1]), ["wifi-scan", {device: "wlan0"}]);
            findChild(wifi, "wifi-device").forceActiveFocus(); keyClick(Qt.Key_Down);
            compare(Array.from(device.signalArguments[0]), ["wlan1"]);
        }
        function test_busy_prevents_duplicate_operations() {
            wifi.selected = wifi.snapshot.wifiNetworks[2]; wifi.busy = true;
            mouseClick(findChild(wifi, "wifi-power")); mouseClick(findChild(wifi, "wifi-scan"));
            mouseClick(findChild(wifi, "wifi-connect")); compare(control.count, 0);
        }
        function test_password_cleared_on_selection_and_close() {
            wifi.selected = wifi.snapshot.wifiNetworks[1];
            const password = findChild(wifi, "wifi-password"); password.text = "test password";
            mouseClick(findChild(wifi, "wifi-network-Cafe")); compare(password.text, "");
            wifi.selected = wifi.snapshot.wifiNetworks[1]; password.text = "test password";
            wifi.visible = false; compare(password.text, ""); compare(wifi.selected, null);
        }
        function test_status_and_inline_errors() {
            compare(findChild(wifi, "wifi-status").text, "Connected to Home");
            wifi.error = "Wrong password"; compare(findChild(wifi, "wifi-error").text, "Wrong password");
            wifi.busy = true; wifi.busyAction = "wifi-connect";
            compare(findChild(wifi, "wifi-status").text, "Connecting…");
        }
    }
}
