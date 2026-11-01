import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    NotificationSource { id: notifications; profile: Quickshell.shellDir }
    QtObject { id: fakeAudio; property real volume: 0.5; property bool muted: false }
    VolumeSource {
        id: volumeSource
        audio: fakeAudio
        onVolumeChanged: (percentage, muted) => notifications.notifyVolume(percentage, muted)
    }
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
        function battery(level: string, percentage: int): void { notifications.notifyBattery(level, percentage, 3); }
        function volume(percentage: int, muted: bool): void { notifications.notifyVolume(percentage, muted); }
        function resetAudio(level: real, muted: bool): void { fakeAudio.volume = level; fakeAudio.muted = muted; }
        function availability(enabled: bool): void { volumeSource.audio = enabled ? fakeAudio : null; }
        function changeAndRead(amount: int): string {
            const accepted = volumeSource.change(amount);
            return JSON.stringify({ok: accepted, volume: fakeAudio.volume, muted: fakeAudio.muted, toast: notifications.toast?.summary || ""});
        }
        function dismiss(): void { notifications.toast.dismiss(); }
        function charged(): void { notifications.clearBattery(); }
    }
}
