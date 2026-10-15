pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../roles/desktop/files/shell" as Desktop
import "../../../roles/desktop/files/shared" as Shared

ShellRoot {
    id: root
    property int stage: 0
    property bool failed: false
    readonly property string field: "general.lockPowerRequiresAuth"
    function check(condition, description) {
        if (!condition) { failed = true; console.error("Settings fixture failed: " + description); Qt.quit(); }
        return condition;
    }
    Component.onCompleted: Quickshell.watchFiles = false
    Shared.SettingsSource {
        id: source
        profile: Quickshell.shellDir + "/.."
        onSnapshotChanged: store.receive(snapshot)
        onErrorChanged: store.sourceError = error
    }
    Desktop.SettingsStore {
        id: store
        onApplyRequested: request => backend.send(request)
    }
    Shared.SettingsBackend {
        id: backend
        profile: source.profile
        onFinished: response => store.finish(response)
    }
    FileView { id: writer; path: source.profile + "/settings.json"; printErrors: false }
    Item {
        width: 1280; height: 800
        Desktop.ConfigurationWindow { id: configuration; anchors.fill: parent; store: store }
    }
    Timer {
        interval: 40; repeat: true; running: true
        onTriggered: {
            if (root.failed) return;
            if (root.stage === 0 && store.loaded) {
                if (!root.check(store.draft[root.field] === true, "initial defaults")) return;
                store.edit(root.field, false);
                configuration.query = "LOGIN password";
                if (!root.check(configuration.results.length === 1 && store.dirty, "search preserves draft")) return;
                store.apply();
                root.stage = 1;
            } else if (root.stage === 1 && !store.busy && !store.dirty && source.preferences.lockPowerRequiresAuth === false) {
                if (!root.check(!store.error, "apply and file observation")) return;
                store.edit(root.field, true);
                writer.setText(JSON.stringify({schemaVersion: 1, revision: 2, general: {lockPowerRequiresAuth: false}}));
                root.stage = 2;
            } else if (root.stage === 2 && store.conflict) {
                if (!root.check(store.draft[root.field] === true && !store.canApply, "dirty draft retained after external change")) return;
                store.revert();
                if (!root.check(store.draft[root.field] === false && !store.conflict, "revert adopts external revision")) return;
                writer.setText("not JSON");
                root.stage = 3;
            } else if (root.stage === 3 && source.error) {
                if (!root.check(source.preferences.lockPowerRequiresAuth === true && store.sourceError.length > 0, "malformed override fails closed")) return;
                writer.setText(JSON.stringify({schemaVersion: 1, revision: 3, general: {lockPowerRequiresAuth: true}}));
                root.stage = 4;
            } else if (root.stage === 4 && !source.error && !store.sourceError && store.draft[root.field] === true) {
                console.log("ARCHSETUP_SETTINGS_FIXTURES_PASSED");
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: root.check(false, "timed out at stage " + root.stage) }
}
