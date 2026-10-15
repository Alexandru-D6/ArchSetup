pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: source
    required property string path
    property var snapshot: ({})
    FileView {
        path: source.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const value = JSON.parse(text());
                if (typeof value.timestamp === "number" && typeof value.date === "string") source.snapshot = value;
            } catch (error) { console.warn("Cannot read clock snapshot"); }
        }
    }
}
