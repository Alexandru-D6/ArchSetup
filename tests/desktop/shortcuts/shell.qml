pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property int stage: 0
    property bool failed: false
    function check(condition, description) {
        if (!condition) {
            failed = true;
            console.error("Shortcut fixture failed: " + description);
            Qt.quit();
        }
        return condition;
    }
    Component.onCompleted: Quickshell.watchFiles = false
    ShortcutSource { id: source; path: Quickshell.shellDir + "/../shortcuts.json" }
    FileView { id: writer; path: source.path }
    Item {
        width: 1280; height: 800
        ShortcutHelp { id: help; anchors.fill: parent; bindings: source.bindings; loadError: source.loadError }
    }
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (root.failed) return;
            if (root.stage === 0 && source.bindings.length > 200) {
                help.query = "Super + Shift + S";
                if (!root.check(help.matchCount === 2, "production key search")) return;
                root.stage = 1;
                writer.setText(JSON.stringify([
                    {key: "SUPER + SHIFT + S", description: "Updated screen snip", category: "Capture"},
                    {key: "SUPER + W", description: "Browser", category: "Applications"}
                ]));
            } else if (root.stage === 1 && source.bindings.length === 2) {
                if (!root.check(help.matchCount === 1 && help.categories[0].name === "Capture", "map reload reapplies search")) return;
                root.stage = 2;
                writer.setText("[null]");
            } else if (root.stage === 2 && source.loadError.length > 0) {
                if (!root.check(source.bindings.length === 0 && help.matchCount === 0, "invalid map clears stale results")) return;
                root.stage = 3;
                writer.setText("not JSON");
                source.loadError = "";
            } else if (root.stage === 3 && source.loadError.length > 0) {
                if (!root.check(help.matchCount === 0, "malformed JSON is handled")) return;
                root.stage = 4;
                writer.setText(JSON.stringify([{key: "SUPER + SHIFT + S", description: "Recovered screen snip", category: "Capture"}]));
            } else if (root.stage === 4 && source.bindings.length === 1 && !source.loadError) {
                if (!root.check(help.matchCount === 1 && help.matches[0].description === "Recovered screen snip", "valid file recovers")) return;
                console.log("ARCHSETUP_SHORTCUT_FIXTURES_PASSED");
                Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: root.check(false, "timed out at stage " + root.stage) }
}
