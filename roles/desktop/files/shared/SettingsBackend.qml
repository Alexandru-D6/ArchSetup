pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: backend
    required property string profile
    property bool busy: false
    property var request: ({})
    signal finished(var response)

    function send(payload) {
        if (busy) return false;
        request = payload;
        busy = true;
        process.stdinEnabled = true;
        process.running = true;
        timeout.restart();
        return true;
    }
    function complete(response) {
        if (!busy) return;
        timeout.stop();
        busy = false;
        finished(response);
    }
    Process {
        id: process
        command: [backend.profile + "/bin/desktop-settings"]
        onStarted: { write(JSON.stringify(backend.request) + "\n"); stdinEnabled = false; }
        stdout: StdioCollector { id: output }
        stderr: StdioCollector {}
        // Quickshell's qmltypes omit the QProcess::ExitStatus enum even when
        // the handler only consumes exitCode. The runtime signal is tested.
        // qmllint disable signal-handler-parameters
        onExited: exitCode => {
            try {
                const response = JSON.parse(output.text);
                if (typeof response.ok !== "boolean" || (response.ok && (exitCode !== 0 || (!response.snapshot && !response.catalog && !response.clock))))
                    throw new Error("Invalid settings response");
                backend.complete(response);
            } catch (error) {
                backend.complete({ok: false, code: "backend", message: "The settings helper could not complete the request. Reapply the desktop profile and retry."});
            }
        }
        // qmllint enable signal-handler-parameters
    }
    Timer {
        id: timeout
        interval: backend.request.operation === "apply" || backend.request.operation === "recover" ? 300000 : 10000
        onTriggered: {
            process.running = false;
            backend.complete({ok: false, code: "timeout", message: "The settings request timed out. Reload the current values before retrying."});
        }
    }
}
