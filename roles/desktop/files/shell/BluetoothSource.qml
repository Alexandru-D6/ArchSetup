import QtQuick
import Quickshell.Io

Item {
    id: source
    required property string profile
    property bool active: false
    property bool discovery: false
    property bool ready: false
    property bool busy: false
    property string operation: ""
    property var snapshot: ({})
    property var prompt: null
    property string error: ""
    function change(action, value) {
        if (!ready || !worker.running) return;
        if (busy && !["scan", "cancel", "respond"].includes(action)) return;
        error = "";
        if (["power", "pair", "connect", "disconnect", "forget"].includes(action)) busy = true;
        worker.write(JSON.stringify({action: action, value: value}) + "\n");
    }
    function receive(text) {
        try {
            const response = JSON.parse(text);
            const scan = discovery && response.state?.bluetoothEnabled
                && (!ready || !snapshot.bluetoothEnabled || snapshot.bluetoothAdapter !== response.state.bluetoothAdapter);
            snapshot = response.state || {};
            busy = response.busy === true;
            operation = response.operation || "";
            // Discovery updates must not reset a PIN the user is typing.
            const nextPrompt = response.prompt || null;
            if (JSON.stringify(prompt) !== JSON.stringify(nextPrompt)) prompt = nextPrompt;
            error = response.error || "";
            ready = true;
            if (scan) change("scan", true);
        } catch (e) { error = "Could not read Bluetooth status."; }
    }
    onDiscoveryChanged: {
        if (!discovery) { change("cancel", null); change("scan", false); }
        else if (snapshot.bluetoothEnabled) change("scan", true);
    }
    Process {
        id: worker
        running: source.active
        command: [source.profile + "/bin/desktop-bluetooth"]
        stdinEnabled: true
        onStarted: { source.ready = false; source.error = ""; }
        stdout: SplitParser { onRead: data => source.receive(data) }
        onExited: (code, status) => {
            source.ready = false; source.busy = false; source.prompt = null; source.operation = "";
            if (source.active) source.error = "Bluetooth controls stopped. Close and reopen the panel to retry.";
        }
    }
}
