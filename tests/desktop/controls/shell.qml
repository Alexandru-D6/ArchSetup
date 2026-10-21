import QtQuick
import Quickshell
import "./"

ShellRoot {
    id: root
    property int stage: 0
    Component.onCompleted: Quickshell.watchFiles = false
    ControlSource { id: source; profile: Quickshell.shellDir; active: true }
    Timer {
        interval: 25; running: true; repeat: true
        onTriggered: {
            if (root.stage === 0 && source.snapshot.wifiAvailable) {
                source.change("wifi-connect", {device: "wlan0", ssid: "Home", security: "psk", passphrase: "test password"});
                root.stage = 1;
            } else if (root.stage === 1 && !source.busy && source.snapshot.wifiName === "Home") {
                if (source.pendingRequest !== "" || source.error !== "") { console.error("Request was not cleared"); Qt.quit(); return; }
                source.change("wifi-disconnect", {device: "wlan0"});
                root.stage = 2;
            } else if (root.stage === 2 && !source.busy && source.error === "Test failure") {
                source.selectWifi("wlan1");
                root.stage = 3;
            } else if (root.stage === 3 && source.snapshot.wifiDevice === "wlan1" && !source.error) {
                console.log("ARCHSETUP_CONTROLS_PASSED"); Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("Timed out at stage " + root.stage); Qt.quit(); } }
}
