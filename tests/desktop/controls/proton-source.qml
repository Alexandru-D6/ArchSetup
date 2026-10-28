import QtQuick
import Quickshell
import "./"

ShellRoot {
    id: root
    property int step: 0
    property int ticks: 0
    Component.onCompleted: Quickshell.watchFiles = false
    function fail(message) { console.error(message); Qt.quit(); }
    ProtonSource { id: source; profile: Quickshell.shellDir; active: true }
    Timer {
        interval: 20; repeat: true; running: true
        onTriggered: {
            root.ticks++;
            if (root.ticks > 200 || source.error) { root.fail("Proton source failed: " + source.error + " step " + root.step); return; }
            if (root.step === 0 && source.snapshot.vpnStatus === "disconnected") {
                source.refresh(); source.change("connect", "ES"); source.change("disconnect", null);
                if (!source.busy) { root.fail("Queued connection is not busy"); return; }
                root.step = 1;
            } else if (root.step === 1 && !source.busy && source.snapshot.vpnConnected) {
                source.active = false;
                root.step = 2;
            } else if (root.step === 2) {
                if (!source.snapshot.vpnConnected) { root.fail("Panel close disconnected VPN"); return; }
                source.change("disconnect", null); root.step = 3;
            } else if (root.step === 3 && !source.busy && source.snapshot.vpnStatus === "disconnected") {
                console.log("ARCHSETUP_PROTON_SOURCE_PASSED"); Qt.quit();
            }
        }
    }
}
