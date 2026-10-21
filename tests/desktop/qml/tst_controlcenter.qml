import QtQuick
import QtTest
import "../../../roles/desktop/files/shell"

Item {
    width: 440; height: 900
    ControlCenter { id: center; anchors.fill: parent }
    SignalSpy { id: control; target: center; signalName: "controlRequested" }
    SignalSpy { id: launch; target: center; signalName: "launchRequested" }
    SignalSpy { id: power; target: center; signalName: "powerRequested" }
    SignalSpy { id: settings; target: center; signalName: "settingsRequested" }
    SignalSpy { id: close; target: center; signalName: "closed" }
    SignalSpy { id: night; target: center; signalName: "nightRequested" }
    SignalSpy { id: dnd; target: center; signalName: "dndRequested" }
    SignalSpy { id: clear; target: center; signalName: "clearRequested" }
    TestCase {
        name: "ControlCenter"
        when: windowShown
        function init() {
            center.snapshot = {uptime: 93780, wifiAvailable: true, wifiEnabled: true, wifiName: "Home", wifiDevice: "wlan0",
                bluetoothAvailable: true, bluetoothEnabled: false, nightAvailable: true,
                output: "speakers", outputs: [{id: "speakers", name: "Speakers", volume: 42, muted: false}, {id: "headphones", name: "Headphones", volume: 50, muted: false}],
                input: "mic", inputs: [{id: "mic", name: "Microphone", muted: true}],
                vpns: [{id: "vpn-1", name: "Work", active: false}, {id: "vpn-2", name: "Home", active: true}]};
            center.audioDetails = false; center.vpnDetails = false; center.wifiDetails = false; center.selectedVpn = "";
            center.bluetoothDetails = false; center.bluetoothReady = true; center.bluetoothBusy = false; center.bluetoothError = ""; center.bluetoothPrompt = null;
            center.busy = false; center.error = ""; center.notifications = []; center.nightEnabled = false;
            control.clear(); launch.clear(); power.clear(); settings.clear(); close.clear(); night.clear(); dnd.clear(); clear.clear();
            wait(50);
        }
        function test_header_and_escape() {
            compare(findChild(center, "uptime").text, "Up 1d 2h 3m");
            mouseClick(findChild(center, "settings")); compare(settings.count, 1);
            mouseClick(findChild(center, "power")); compare(power.count, 1);
            center.forceActiveFocus(); keyClick(Qt.Key_Escape); compare(close.count, 1);
        }
        function test_toggle_requests_use_actual_state() {
            mouseClick(findChild(center, "bluetooth"), 60, 30); compare(Array.from(control.signalArguments[0]), ["bluetooth", true]);
            mouseClick(findChild(center, "mic"), 60, 30); compare(Array.from(control.signalArguments[1]), ["mic", false]);
            mouseClick(findChild(center, "audio-mute")); compare(Array.from(control.signalArguments[2]), ["mute", true]);
            // Active VPN is selected before inactive profiles.
            mouseClick(findChild(center, "vpn"), 60, 30); compare(Array.from(control.signalArguments[3]), ["vpn", "vpn-2"]);
            mouseClick(findChild(center, "night"), 60, 30); compare(night.count, 1);
        }
        function test_missing_hardware_cannot_toggle() {
            center.snapshot = {}; wait(10);
            for (const name of ["wifi", "bluetooth", "mic", "night"]) mouseClick(findChild(center, name), 60, 30);
            compare(control.count, 0); compare(night.count, 0);
            verify(!findChild(center, "audio-output").enabled);
            mouseClick(findChild(center, "vpn"), 60, 30); compare(Array.from(launch.signalArguments[0]), ["network"]);
        }
        function test_details_do_not_toggle_device() {
            const wifi = findChild(center, "wifi");
            mouseClick(wifi, wifi.width - 18, 30);
            verify(center.wifiDetails); compare(launch.count, 0);
            compare(Array.from(control.signalArguments[0]), ["wifi-scan", {device: "wlan0"}]);
            center.forceActiveFocus(); keyClick(Qt.Key_Escape); verify(!center.wifiDetails); compare(close.count, 0);
            control.clear(); wait(10);
            const mic = findChild(center, "mic");
            mouseClick(mic, mic.width - 18, 30);
            verify(findChild(center, "audio-input").visible); compare(control.count, 0);
        }
        function test_wifi_tile_toggles_power_and_arrow_opens_connections() {
            const wifi = findChild(center, "wifi");
            mouseClick(wifi, 60, 30);
            compare(Array.from(control.signalArguments[0]), ["wifi-power", {device: "wlan0", enabled: false}]);
            verify(!center.wifiDetails);
            center.snapshot = Object.assign({}, center.snapshot, {wifiEnabled: false}); wait(10);
            mouseClick(wifi, 60, 30);
            compare(Array.from(control.signalArguments[1]), ["wifi-power", {device: "wlan0", enabled: true}]);
            verify(!center.wifiDetails);
            control.clear();
            mouseClick(wifi, wifi.width - 18, 30);
            verify(findChild(center, "wifi-panel").visible); compare(launch.count, 0); compare(close.count, 0);
            compare(control.count, 0);
            mouseClick(findChild(center, "wifi-back")); verify(!center.wifiDetails);
            center.snapshot = {wifiError: "iwd is unavailable"}; control.clear(); wait(10);
            mouseClick(wifi, wifi.width - 18, 30); verify(center.wifiDetails);
            compare(findChild(center, "wifi-error").text, "iwd is unavailable");
            verify(!findChild(center, "wifi-power").enabled); compare(control.count, 0);
        }
        function test_busy_prevents_duplicate_writes() {
            center.busy = true;
            mouseClick(findChild(center, "wifi"), 60, 30);
            mouseClick(findChild(center, "vpn"), 60, 30);
            compare(control.count, 0);
        }
        function test_bluetooth_arrow_opens_inline_without_toggling_power() {
            const bluetooth = findChild(center, "bluetooth");
            mouseClick(bluetooth, bluetooth.width - 18, 30);
            verify(center.bluetoothDetails); verify(findChild(center, "bluetooth-panel").visible);
            compare(control.count, 0); compare(launch.count, 0); compare(close.count, 0);
            center.forceActiveFocus(); keyClick(Qt.Key_Escape);
            verify(!center.bluetoothDetails); compare(close.count, 0);
            mouseClick(bluetooth, 60, 30);
            compare(Array.from(control.signalArguments[0]), ["bluetooth", true]);
            verify(!center.bluetoothDetails);
            center.bluetoothBusy = true; control.clear();
            mouseClick(bluetooth, 60, 30); compare(control.count, 0);
        }
        function test_output_selection_and_color_picker() {
            const output = findChild(center, "audio-output");
            output.forceActiveFocus(); keyClick(Qt.Key_Down);
            compare(Array.from(control.signalArguments[0]), ["output", "headphones"]);
            mouseClick(findChild(center, "color"), 60, 30); compare(Array.from(launch.signalArguments[0]), ["color"]);
        }
        function test_notifications_and_dnd() {
            mouseClick(findChild(center, "dnd")); compare(dnd.count, 1);
            verify(!findChild(center, "clear").enabled);
            center.notifications = [{appName: "Test", summary: "Notification", body: "Body", actions: []}];
            wait(20); mouseClick(findChild(center, "clear")); compare(clear.count, 1);
            compare(findChild(center, "notifications").count, 1);
        }
    }
}
