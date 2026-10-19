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
    property var toast: null
    readonly property var notifications: serverLoader.item ? serverLoader.item.trackedNotifications.values.slice().reverse().filter(n => !n.transient) : []
    function clear() { for (const item of notifications.slice()) item.dismiss(); }
    function hideToast() {
        const previous = toast;
        toast = null;
        if (previous?.transient) previous.expire();
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
                    if (service.toast !== notification) service.hideToast();
                    service.toast = notification;
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
        target: service.toast
        function onClosed(reason) { service.toast = null; }
    }
    Timer { id: timeout; onTriggered: service.hideToast() }
}
