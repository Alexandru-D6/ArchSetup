pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: source
    required property string profile
    property bool live: true
    property var snapshot: null
    property var preferences: ({lockPowerRequiresAuth: true})
    property string error: ""
    property string errorCode: ""
    property bool pending: false
    function refresh() {
        if (reader.busy) { pending = true; return; }
        reader.send({operation: "read"});
    }
    Component.onCompleted: refresh()
    SettingsBackend {
        id: reader
        profile: source.profile
        onFinished: response => {
            if (response.ok) {
                source.preferences = response.snapshot.preferences;
                source.snapshot = response.snapshot;
                source.error = "";
                source.errorCode = "";
            } else if (response.code !== "busy") {
                source.preferences = Object.assign({}, source.preferences, {lockPowerRequiresAuth: true});
                source.error = response.message || "Unable to read settings.";
                source.errorCode = response.code || "read";
            }
            if (source.pending) { source.pending = false; Qt.callLater(source.refresh); }
        }
    }
    FileView {
        path: source.profile + "/preferences.json"
        watchChanges: source.live
        printErrors: false
        onFileChanged: { reload(); source.refresh(); }
    }
    FileView {
        path: source.profile + "/settings.json"
        watchChanges: source.live
        printErrors: false
        onFileChanged: { reload(); source.refresh(); }
    }
    // Also detect a file created after startup or changes missed during resume.
    Timer { interval: 5000; running: source.live; repeat: true; onTriggered: source.refresh() }
}
