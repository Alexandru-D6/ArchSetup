pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pam

// Run inside qs: its PAM plugin is statically linked into that executable.
// These fixtures never create a lock, use system policies, or log responses.
ShellRoot {
    id: root
    property var cases: [
        {config: "deny", success: false},
        {config: "required-deny", success: false},
        {config: "missing-policy", success: false, startup: true},
        {config: "prompt-deny", success: false, prompt: true},
        {config: "prompt-accept", success: true, prompt: true},
        {config: "accept", success: true}
    ]
    property int index: -1
    property int successes: 0
    property int clearings: 0
    property int prompts: 0
    property bool failed: false
    function check(condition, description) {
        if (!condition) {
            failed = true;
            console.error("PAM fixture failed: " + description);
            Qt.quit();
        }
        return condition;
    }
    function next() {
        if (failed) return;
        index++;
        if (index === cases.length) {
            console.log("ARCHSETUP_PAM_FIXTURES_PASSED");
            Qt.quit();
            return;
        }
        auth.busy = false;
        auth.context.config = cases[index].config;
        successes = 0;
        clearings = 0;
        prompts = 0;
        auth.submit("dummy response");
        if (cases[index].startup) {
            if (!check(!auth.busy && auth.pendingResponse === "" && !auth.hasPendingResponse, "missing policy cleanup")) return;
            if (!check(successes === 0 && clearings === 1 && auth.message.length > 0, "missing policy feedback")) return;
            Qt.callLater(next);
            return;
        }
        auth.submit("ignored duplicate");
    }
    function completed(result) {
        const spec = cases[index];
        if (!check((result === PamResult.Success) === spec.success, spec.config + " result")) return;
        if (!check(successes === (spec.success ? 1 : 0), spec.config + " success signal")) return;
        if (!check(auth.pendingResponse === "" && !auth.hasPendingResponse, "response cleanup")) return;
        if (!check(clearings === 2, "duplicate submission or missing clearing")) return;
        if (!check(auth.busy === spec.success, "busy state")) return;
        if (!spec.success && !check(auth.message.length > 0, "failure feedback")) return;
        if (spec.prompt && !check(prompts > 0, "password prompt")) return;
        Qt.callLater(next);
    }
    Component.onCompleted: {
        Quickshell.watchFiles = false;
        const user = auth.context.user;
        auth.context.config = "accept";
        auth.context.user = "archsetup_pam_fixture_does_not_exist";
        auth.submit("dummy response");
        if (!check(!auth.busy && auth.pendingResponse === "" && !auth.hasPendingResponse, "startup failure cleanup")) return;
        auth.context.user = user;
        next();
    }
    LockAuth {
        id: auth
        context.configDirectory: Quickshell.shellDir
        onSucceeded: root.successes++
        onCleared: root.clearings++
    }
    Connections {
        target: auth.context
        function onPamMessage() { if (auth.context.responseRequired) root.prompts++; }
        function onCompleted(result) { Qt.callLater(() => root.completed(result)); }
    }
    Timer {
        interval: 12000
        running: true
        onTriggered: root.check(false, "timed out")
    }
}
