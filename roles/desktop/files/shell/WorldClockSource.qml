pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: source
    property var times: ({})
    property string error: ""
    property bool active: true
    property double sampledMinute: -1
    onActiveChanged: if (active) refresh()
    function refresh() {
        if (!reader.running) { sampledMinute = Math.floor(Date.now() / 60000); reader.running = true; }
    }
    Component.onCompleted: refresh()
    Timer { interval: 1000; repeat: true; running: source.active; onTriggered: if (source.sampledMinute !== Math.floor(Date.now() / 60000)) source.refresh() }
    Process {
        id: reader
        // Use the system IANA database, including DST and fractional UTC offsets.
        command: ["python3", "-c", "import json; from datetime import datetime, timezone; from zoneinfo import ZoneInfo, available_timezones; now = datetime.now(timezone.utc); print(json.dumps({zone: {'hour': local.hour, 'minute': local.minute} for zone in sorted(available_timezones()) for local in [now.astimezone(ZoneInfo(zone))]}))"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { source.times = JSON.parse(text); source.error = ""; }
                catch (error) { source.error = "Could not load the system timezone database."; }
            }
        }
        onExited: (code, status) => { if (code !== 0) source.error = "Could not load the system timezone database."; }
    }
}
