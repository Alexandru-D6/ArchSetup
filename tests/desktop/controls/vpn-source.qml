import QtQuick
import Quickshell

ShellRoot {
    id: root
    property int step: 0
    property int ticks: 0
    Component.onCompleted: Quickshell.watchFiles = false
    function fail(message) { console.error(message); Qt.quit(); }
    VpnSource { id: source; profile: Quickshell.shellDir; active: true }
    Timer {
        interval: 20; repeat: true; running: true
        onTriggered: {
            root.ticks++;
            if (root.ticks > 400 || source.error) { root.fail("VPN source failed: " + source.error + " step " + root.step); return; }
            if (root.step === 0 && source.snapshot.vpnProvider === "proton") {
                source.refresh();
                source.change("select-provider", "tailscale");
                source.change("disconnect", null);
                if (!source.busy) { root.fail("Provider change was not queued"); return; }
                root.step = 1;
            } else if (root.step === 1 && !source.busy && source.snapshot.vpnProvider === "tailscale") {
                source.change("connect", "");
                root.step = 2;
            } else if (root.step === 2 && !source.busy && source.snapshot.vpnConnected) {
                source.active = false;
                source.change("select-provider", "proton");
                root.step = 3;
            } else if (root.step === 3 && !source.busy && source.snapshot.vpnProvider === "proton") {
                if (!source.snapshot.vpnConnected) { root.fail("Switching providers disconnected Proton"); return; }
                console.log("ARCHSETUP_VPN_SOURCE_PASSED"); Qt.quit();
            }
        }
    }
}
