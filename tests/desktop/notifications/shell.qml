import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    NotificationSource { id: notifications; profile: Quickshell.shellDir }
    IpcHandler {
        target: "test"
        function status(): string {
            return JSON.stringify({count: notifications.notifications.length, toast: notifications.toast?.summary || "", dnd: notifications.dnd,
                entries: notifications.notifications.map(n => ({id: n.id, summary: n.summary, body: n.body}))});
        }
        function quiet(enabled: bool): void { notifications.dnd = enabled; }
        function opened(enabled: bool): void { notifications.panelOpen = enabled; }
        function clear(): void { notifications.clear(); }
        function invoke(): void { notifications.notifications[0].actions[0].invoke(); }
    }
}
