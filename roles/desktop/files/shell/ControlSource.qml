import QtQuick
import Quickshell.Io

Item {
    id: source
    required property string profile
    property bool active: false
    property var snapshot: ({})
    property string error: ""
    readonly property bool busy: writer.running
    readonly property bool nightEnabled: night.running
    property bool nightWanted: false
    function refresh() { if (!reader.running && !writer.running) reader.running = true; }
    function change(action, value) {
        if (busy) return;
        error = "";
        // Discard any older poll that finishes during this write.
        reader.running = false;
        writer.command = [profile + "/bin/desktop-controls", JSON.stringify({action: action, value: value})];
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
        command: [source.profile + "/bin/desktop-controls"]
        stdout: StdioCollector { onStreamFinished: if (!source.busy) source.receive(text) }
    }
    Process {
        id: writer
        stdout: StdioCollector { onStreamFinished: source.receive(text) }
        onExited: source.refresh()
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
