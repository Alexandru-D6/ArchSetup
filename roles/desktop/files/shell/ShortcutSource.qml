pragma ComponentBehavior: Bound
import QtQml
import Quickshell.Io

QtObject {
    id: source
    property string path
    property var bindings: []
    property string loadError: ""
    readonly property FileView reader: FileView {
        path: source.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const bindings = JSON.parse(text());
                if (!Array.isArray(bindings) || !bindings.every(item => item && typeof item.key === "string" && typeof item.description === "string" && (item.category === undefined || typeof item.category === "string"))) throw new Error("Invalid shortcut map");
                source.bindings = bindings;
                source.loadError = "";
            } catch (e) {
                source.bindings = [];
                source.loadError = "Could not load shortcuts";
                console.warn(e);
            }
        }
        onLoadFailed: { source.bindings = []; source.loadError = "Could not load shortcuts"; }
    }
}
