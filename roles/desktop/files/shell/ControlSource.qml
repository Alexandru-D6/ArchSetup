import QtQuick
import Quickshell.Io

Item {
    id: source
    required property string profile
    property bool active: false
    property var snapshot: ({})
    property string error: ""
    property string wifiDevice: ""
    property string busyAction: ""
    property string pendingRequest: ""
    property int revision: 0
    readonly property bool busy: writer.running
    readonly property bool nightEnabled: night.running
    property bool nightWanted: false
    function refresh() {
        if (reader.running || writer.running) return;
        reader.revision = revision;
        reader.command = [profile + "/bin/desktop-controls", JSON.stringify({device: wifiDevice})];
        reader.running = true;
    }
    function selectWifi(device) {
        if (busy) return;
        revision++;
        wifiDevice = device;
        error = "";
        refresh();
    }
    function change(action, value) {
        if (busy) return;
        error = "";
        // Discard any older poll that finishes during this write.
        revision++;
        busyAction = action;
        pendingRequest = JSON.stringify({action: action, value: value, device: wifiDevice});
        writer.running = true;
    }
    function receive(text) {
        try {
            const response = JSON.parse(text);
            if (response.ok) snapshot = response.state;
            else error = response.error || "Could not update controls.";
        } catch (e) { error = "Could not read system controls."; }
    }
    function toggleNight() {
        error = "";
        nightWanted = !nightWanted;
    }
    onActiveChanged: if (active) refresh()
    Process {
        id: reader
        property int revision: 0
        stdout: StdioCollector { onStreamFinished: if (!source.busy && reader.revision === source.revision) source.receive(text) }
        onExited: if (revision !== source.revision) source.refresh()
    }
    Process {
        id: writer
        command: [source.profile + "/bin/desktop-controls", "--stdin"]
        stdinEnabled: true
        onStarted: { write(source.pendingRequest + "\n"); source.pendingRequest = ""; }
        stdout: StdioCollector { onStreamFinished: source.receive(text) }
        onExited: (code, status) => {
            source.pendingRequest = "";
            source.busyAction = "";
            if (code !== 0 || status !== 0) source.error = "Could not update controls.";
            source.refresh();
        }
    }
    Process {
        id: night
        running: source.nightWanted
        command: ["hyprsunset", "--temperature", "4000"]
        onExited: (code, status) => {
            if (source.nightWanted) source.error = "Night light could not start. Check that hyprsunset is available and not already running.";
            source.nightWanted = false;
        }
    }
    Timer { interval: 4000; running: source.active; repeat: true; onTriggered: source.refresh() }
}
