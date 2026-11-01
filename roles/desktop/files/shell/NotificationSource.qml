pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Notifications
import Quickshell.Io

Item {
    id: service
    required property string profile
    property bool active: true
    property bool panelOpen: false
    property bool dnd: false
    property bool loaded: false
    property var applicationToast: null
    property var volumeNotice: null
    property var batteryNotice: null
    property bool batteryVisible: false
    readonly property var toast: batteryVisible ? batteryNotice : volumeNotice || applicationToast
    readonly property var notifications: (batteryNotice ? [batteryNotice] : []).concat(serverLoader.item ? serverLoader.item.trackedNotifications.values.slice().reverse().filter(n => !n.transient) : [])
    function notifyVolume(percentage, muted) {
        if (!Number.isFinite(percentage) || percentage < 0 || percentage > 100) return;
        volumeNotice = {appName: "Audio", summary: "Volume " + Math.round(percentage) + "%" + (muted ? " (muted)" : ""),
            body: "", urgency: NotificationUrgency.Low, actions: [], dismiss: () => clearVolume()};
        volumeTimeout.restart();
    }
    function clearVolume() { volumeTimeout.stop(); volumeNotice = null; }
    function notifyBattery(level, percentage, threshold) {
        const critical = level !== "low";
        const titles = {low: "Battery low", critical: "Battery critically low", suspend: "Battery almost empty",
            suspending: "Suspending for low battery", failed: "Automatic suspend failed"};
        const messages = {
            low: "Connect your charger soon.",
            critical: "Connect your charger now. The computer will suspend below " + threshold + "%.",
            suspend: "Suspending in 5 seconds. Connect power to cancel.",
            suspending: "Connect power before resuming your work.",
            failed: "Save your work and connect power immediately. Suspend manually from the session menu."
        };
        batteryNotice = {appName: "Battery", summary: titles[level], body: percentage + "% remaining. " + messages[level],
            urgency: critical ? NotificationUrgency.Critical : NotificationUrgency.Normal, actions: [],
            dismiss: () => clearBattery()};
        // Power warnings must remain visible even while ordinary alerts are quiet.
        batteryVisible = true;
        batteryTimeout.stop();
        if (!critical && batteryVisible) batteryTimeout.restart();
    }
    function clearBattery() { batteryTimeout.stop(); batteryVisible = false; batteryNotice = null; }
    function clear() { for (const item of notifications.slice()) item.dismiss(); }
    function hideApplicationToast() {
        const previous = applicationToast;
        applicationToast = null;
        if (previous?.transient) previous.expire();
    }
    function hideToast() {
        hideApplicationToast();
    }
    onPanelOpenChanged: if (panelOpen) hideToast()
    onDndChanged: {
        if (dnd) hideToast();
        if (loaded) preferences.setText(JSON.stringify({dnd: dnd}));
    }
    FileView {
        id: preferences
        path: service.profile + "/notifications.json"
        printErrors: false
        onLoaded: {
            try { service.dnd = JSON.parse(text()).dnd === true; } catch (e) { console.warn("Could not load notification preferences"); }
            service.loaded = true;
        }
        onLoadFailed: error => { service.loaded = error === FileViewError.FileNotFound; }
    }
    Loader {
        id: serverLoader
        active: service.active
        sourceComponent: NotificationServer {
            id: server
            keepOnReload: true
            persistenceSupported: true
            bodySupported: true
            bodyMarkupSupported: false
            actionsSupported: true
            imageSupported: false
            inlineReplySupported: false
            onNotification: notification => {
                notification.tracked = true;
                if (!notification.lastGeneration && !service.dnd && !service.panelOpen) {
                    if (service.applicationToast !== notification) service.hideApplicationToast();
                    service.applicationToast = notification;
                    timeout.stop();
                    // The installed notification API preserves the D-Bus timeout in milliseconds.
                    timeout.interval = notification.expireTimeout > 0 ? notification.expireTimeout : 6000;
                    if (notification.expireTimeout !== 0 && notification.urgency !== NotificationUrgency.Critical) timeout.restart();
                } else if (notification.transient) notification.expire();
                // Keep a bounded session history; application close requests still remove entries.
                const entries = server.trackedNotifications.values;
                if (entries.length > 100) entries[0].expire();
            }
        }
    }
    Connections {
        target: service.applicationToast
        function onClosed(reason) { service.applicationToast = null; }
    }
    Timer { id: timeout; onTriggered: service.hideApplicationToast() }
    Timer { id: volumeTimeout; interval: 1500; onTriggered: service.volumeNotice = null }
    Timer { id: batteryTimeout; interval: 10000; onTriggered: service.batteryVisible = false }
}
