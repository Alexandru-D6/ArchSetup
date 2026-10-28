import QtQuick
import Quickshell.Io

Item {
    id: source
    required property string profile
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
        pendingRequest = JSON.stringify({action: action, value: value});
        // The official CLI shares account state; serialize reads and writes.
        if (!reader.running) writer.running = true;
    }
    function receive(text) {
        try {
            const response = JSON.parse(text);
            snapshot = response.state || {};
            error = response.error || "";
        } catch (e) {
            snapshot = {};
            error = "Could not read Proton VPN status.";
        }
    }
    onActiveChanged: if (active) refresh()
    Process {
        id: reader
        command: [source.profile + "/bin/desktop-protonvpn"]
        stdout: StdioCollector { onStreamFinished: if (!source.busy) source.receive(text) }
        onExited: (code, status) => {
            if (source.pendingRequest !== "") writer.running = true;
            else if (code !== 0 || status !== 0) { source.snapshot = {}; source.error = "Could not read Proton VPN status."; }
        }
    }
    Process {
        id: writer
        command: [source.profile + "/bin/desktop-protonvpn", "--stdin"]
        stdinEnabled: true
        onStarted: { write(source.pendingRequest + "\n"); source.pendingRequest = ""; }
        stdout: StdioCollector { onStreamFinished: source.receive(text) }
        onExited: (code, status) => {
            source.pendingRequest = ""; source.operation = "";
            if (code !== 0 || status !== 0) { source.snapshot = {}; source.error = "Proton VPN stopped unexpectedly. Refresh to check the connection."; }
        }
    }
    Timer { interval: 8000; running: source.active; repeat: true; onTriggered: source.refresh() }
}
