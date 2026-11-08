import QtQuick
import Quickshell.Io

Item {
    id: source
    required property string profile
    property string helper: profile + "/bin/desktop-vpn"
    property bool active: false
    property var snapshot: ({})
    property string error: ""
    property string operation: ""
    property string pendingRequest: ""
    readonly property bool busy: pendingRequest !== "" || writer.running
    function refresh() {
        if (!reader.running && !busy) reader.running = true;
    }
    function change(action, value) {
        if (busy) return;
        error = "";
        operation = action;
        pendingRequest = JSON.stringify({provider: snapshot.vpnProvider || "proton", action: action, value: value});
        // Drop any old poll result and finish it before starting the mutation.
        if (!reader.running) writer.running = true;
    }
    function receive(text) {
        try {
            const response = JSON.parse(text);
            snapshot = response.state || {};
            error = response.error || "";
        } catch (e) {
            snapshot = {};
            error = "Could not read VPN status.";
        }
    }
    onActiveChanged: if (active) refresh()
    Process {
        id: reader
        command: [source.helper]
        stdout: StdioCollector { onStreamFinished: if (!source.busy) source.receive(text) }
        onExited: (code, status) => {
            if (source.pendingRequest !== "") writer.running = true;
            else if (code !== 0 || status !== 0) { source.snapshot = {}; source.error = "Could not read VPN status."; }
        }
    }
    Process {
        id: writer
        command: [source.helper, "--stdin"]
        stdinEnabled: true
        onStarted: { write(source.pendingRequest + "\n"); source.pendingRequest = ""; }
        stdout: StdioCollector { onStreamFinished: source.receive(text) }
        onExited: (code, status) => {
            source.pendingRequest = ""; source.operation = "";
            if (code !== 0 || status !== 0) { source.snapshot = {}; source.error = "VPN controls stopped unexpectedly. Refresh to check the connection."; }
        }
    }
    Timer { interval: 8000; running: source.active; repeat: true; onTriggered: source.refresh() }
}
