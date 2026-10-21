import QtQuick
import Quickshell
import "./"

ShellRoot {
    id: root
    property int stage: 0
    property var heldPrompt: null
    Component.onCompleted: Quickshell.watchFiles = false
    BluetoothSource { id: source; profile: Quickshell.shellDir; active: true; discovery: true }
    Timer {
        interval: 25; running: true; repeat: true
        onTriggered: {
            if (root.stage === 0 && source.ready && source.snapshot.bluetoothScanning) {
                source.change("pair", "test-device"); root.stage = 1;
            } else if (root.stage === 1 && source.prompt?.kind === "pin" && source.busy) {
                root.heldPrompt = source.prompt;
                source.change("scan", true); root.stage = 2;
            } else if (root.stage === 2 && source.snapshot.scanCount > 1) {
                if (source.prompt !== root.heldPrompt) { console.error("Status update reset the pairing prompt"); Qt.quit(); return; }
                source.change("respond", "1234"); root.stage = 3;
            } else if (root.stage === 3 && !source.busy && source.snapshot.testConnected) {
                if (source.prompt || source.error) { console.error("Pairing prompt was not cleared"); Qt.quit(); return; }
                source.discovery = false; root.stage = 4;
            } else if (root.stage === 4 && !source.snapshot.bluetoothScanning) {
                source.active = false; root.stage = 5;
            } else if (root.stage === 5 && !source.ready) {
                source.active = true; root.stage = 6;
            } else if (root.stage === 6 && source.ready && !source.snapshot.bluetoothScanning) {
                console.log("ARCHSETUP_BLUETOOTH_SOURCE_PASSED"); Qt.quit();
            }
        }
    }
    Timer { interval: 6000; running: true; onTriggered: { console.error("Timed out at stage " + root.stage); Qt.quit(); } }
}
