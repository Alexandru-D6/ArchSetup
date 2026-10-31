//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "shared" as Desktop

ShellRoot {
    id: root
    readonly property string profile: Quickshell.shellDir + "/.."
    readonly property string lockDirectory: Quickshell.env("ARCHSETUP_LOCK_DIR")
    property var preferences: ({})
    readonly property bool clockReady: lockSettings.snapshot !== null || lockSettings.error !== ""
    property var palette: ({})
    Desktop.ClockSource { id: lockTime; path: root.profile + "/theme/lock-clock.json"; onSnapshotChanged: root.clockRevision++ }
    property string username: ""
    property var layoutNames: ({})
    property string rawLayout: ""
    readonly property string layout: layoutNames[rawLayout] || rawLayout || "US"
    property bool capsLock: false
    property int clearRevision: 0
    property int clockRevision: 0
    property string poweroffLabel: "Power off"
    property string rebootLabel: "Reboot"

    function authenticate(response) {
        if (lock.secure) auth.submit(response);
    }
    Component.onCompleted: {
        if (!lockDirectory) { Qt.quit(); return; }
        // Reloading the lock must never discard an in-flight authentication.
        Quickshell.watchFiles = false;
        lock.locked = true;
    }
    Desktop.SettingsSource {
        id: lockSettings
        profile: root.profile
        live: false
        onPreferencesChanged: root.preferences = preferences
    }
    // A settings Apply can briefly hold the reader's lock at startup. Retry
    // without queuing duplicate reads or delaying the secure lock surface.
    Timer {
        interval: 250
        running: !root.clockReady
        repeat: true
        onTriggered: if (!lockSettings.busy) lockSettings.refresh()
    }
    FileView {
        path: root.profile + "/theme/palette.json"
        onLoaded: { try { root.palette = JSON.parse(text()); } catch (e) { console.warn("Cannot load lock palette"); } }
    }
    FileView {
        path: root.lockDirectory + "/lock-poweroff.label"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.poweroffLabel = text().trim()
    }
    FileView {
        path: root.lockDirectory + "/lock-reboot.label"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.rebootLabel = text().trim()
    }
    Process {
        command: [root.profile + "/bin/lock-visuals", "keyboard-info"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(text);
                    root.username = info.username;
                    root.layoutNames = info.layouts;
                    if (!root.rawLayout) root.rawLayout = info.active;
                    root.capsLock = info.capsLock;
                } catch (e) { console.warn("Cannot load keyboard identity"); }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") root.rawLayout = event.data.slice(event.data.indexOf(",") + 1);
        }
    }
    LockAuth {
        id: auth
        onCleared: root.clearRevision++
        onSucceeded: authenticated.setText("authenticated\n")
    }
    FileView {
        id: authenticated
        path: root.lockDirectory + "/authenticated"
        preload: false
        printErrors: false
        onSaved: { lock.locked = false; Qt.callLater(Qt.quit); }
        onSaveFailed: {
            auth.busy = false;
            auth.message = "Unable to finish unlocking. Try again.";
        }
    }
    WlSessionLock {
        id: lock
        WlSessionLockSurface {
            LockScreen {
                id: screen
                anchors.fill: parent
                profile: root.profile
                clockRevision: root.clockRevision
                clockReady: root.clockReady
                batteryPresent: UPower.displayDevice.ready && UPower.displayDevice.isPresent && UPower.displayDevice.isLaptopBattery
                batteryCharging: UPower.displayDevice.state === UPowerDeviceState.Charging
                powerConnected: !UPower.onBattery
                batteryFull: UPower.displayDevice.state === UPowerDeviceState.FullyCharged
                batteryPercentage: UPower.displayDevice.percentage * 100
                accent: root.palette.accent || "#ffb1c8"
                accentText: root.palette.onAccent || "#56122e"
                clockPosition: root.preferences.clockPlacement?.lockScreen || null
                dateCaption: lockTime.snapshot.date || ""
                controls.username: root.username
                controls.layout: root.layout
                controls.uiFont: root.preferences.font || "DejaVu Sans"
                controls.fontSize: root.preferences.controlFontSize || 12
                controls.reducedMotion: root.preferences.reducedMotion || false
                controls.powerActionsEnabled: root.preferences.lockPowerRequiresAuth === false
                controls.surface: root.palette.raised || "#292332"
                controls.ink: root.palette.ink || "#eae0f5"
                controls.outline: root.palette.outline || "#45404f"
                controls.busy: auth.busy
                controls.message: auth.message
                controls.prompt: auth.prompt
                controls.capsLock: root.capsLock
                controls.poweroffLabel: root.poweroffLabel
                controls.rebootLabel: root.rebootLabel
                Connections {
                    target: screen.controls
                    function onSubmitted(response) { root.authenticate(response); }
                    function onPowerPressed(action) {
                        if (root.preferences.lockPowerRequiresAuth === false)
                            Quickshell.execDetached([root.profile + "/bin/lock-visuals", "click-" + action]);
                    }
                    function onCapsLockToggled() { root.capsLock = !root.capsLock; }
                }
                Connections {
                    target: root
                    function onClearRevisionChanged() { screen.controls.clearPassword(); }
                }
            }
        }
    }
}
