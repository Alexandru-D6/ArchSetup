//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs
import "shared"

ShellRoot {
    id: root
    property string page: ""
    onPageChanged: focusTimer.restart()
    Timer {
        id: focusTimer
        interval: 50
        onTriggered: {
            if (root.page === "overview") windows.forceActiveFocus();
            else if (root.page === "session") sessionMenu.forceActiveFocus();
            else if (root.page === "help") shortcutHelp.focusSearch();
            else if (root.page !== "") panelContent.forceActiveFocus();
            else if (root.configurationOpen) root.focusConfiguration();
        }
    }
    property bool timeCenterOpen: false
    property string timeCenterScreen: ""
    property bool zonesLoaded: false
    property string zoneError: ""
    property bool tasksLoaded: false
    property string taskError: ""
    property bool inhibitIdle: false
    property bool barVisible: true
    property bool barBottom: false
    property bool desktopClockVisible: true
    property bool toolsDetached: false
    property bool keyboardVisible: false
    property bool keyboardShift: false
    property bool keyboardControl: false
    property bool configurationOpen: false
    property string configurationScreenName: ""
    property var preferences: ({})
    property var userState: ({})
    property bool light: typeof userState.light === "boolean" ? userState.light : palette.light !== false
    property var palette: ({})
    property string uiFont: preferences.font || "DejaVu Sans"
    property color surface: palette.surface || (light ? "#fff8f9" : "#21161c")
    property color raised: palette.raised || (light ? "#ffe7eb" : "#35242c")
    property color ink: palette.ink || (light ? "#3d2c32" : "#f9e2e8")
    property color accent: palette.accent || (light ? "#bd0056" : "#ffb1c8")
    property color onAccent: palette.onAccent || (light ? "#ffffff" : "#56122e")
    property string wallpaper: profile + "/theme/wallpaper.png"
    property int wallpaperRevision: 0
    property int clockRevision: 0
    property string profile: Quickshell.shellDir + "/.."
    property var status: ({volume: "—", network: "—", brightness: false})
    function action(name) { Quickshell.execDetached([profile + "/bin/desktop-action", name]); }
    function refreshClock() { if (palette.primaryContainer && !clockProcess.running) clockProcess.running = true; }
    function toggle(name) {
        if (name === "configuration") { openConfiguration(); return; }
        if (name === "session") sessionMenu.select("lock");
        page = page === name ? "" : name;
    }
    function openConfiguration() {
        if (!configurationOpen) {
            configurationScreenName = Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
            configurationOpen = true;
            settingsSource.refresh();
            configurationWindow.focusSearch();
        }
        page = "";
        focusTimer.restart();
    }
    function focusConfiguration() {
        if (settingsStore.busy) return;
        configurationWindow.focusForm();
        configurationFocus.active = true;
    }
    function shutdown() {
        sessionMenu.select("poweroff");
        page = "session";
        sessionMenu.forceActiveFocus();
    }
    function workspace(number) { Hyprland.dispatch("hl.dsp.focus({workspace=" + number + "})"); }
    function workspaceStart(active, count) { return Math.floor((Math.max(1, active || 1) - 1) / count) * count + 1; }
    function control(name) {
        if (name === "bar") barVisible = !barVisible;
        else if (name === "bar-position") barBottom = !barBottom;
        else if (name === "widgets") desktopClockVisible = !desktopClockVisible;
        else if (name === "keyboard") keyboardVisible = !keyboardVisible;
        else if (name === "keep-awake") inhibitIdle = !inhibitIdle;
        else if (name === "detach-tools") { page = ""; toolsDetached = !toolsDetached; }
    }
    function utility(name) { page = ""; toolsDetached = false; action(name); }
    function typeKey(key) {
        if (key === "Shift") { keyboardShift = !keyboardShift; return; }
        if (key === "Ctrl") { keyboardControl = !keyboardControl; return; }
        const mods = [keyboardShift ? "SHIFT" : "", keyboardControl ? "CTRL" : ""].filter(Boolean).join(" + ");
        Hyprland.dispatch("hl.dsp.send_shortcut({mods=" + JSON.stringify(mods) + ",key=" + JSON.stringify(key) + "})");
        keyboardShift = false;
    }
    ShortcutSource {
        id: shortcutSource
        path: root.profile + "/shortcuts.json"
    }
    SettingsSource {
        id: settingsSource
        profile: root.profile
        onPreferencesChanged: {
            const timezoneChanged = root.preferences.timezone !== preferences.timezone;
            root.preferences = preferences;
            if (timezoneChanged) root.refreshClock();
        }
        onSnapshotChanged: settingsStore.receive(snapshot)
        onErrorChanged: settingsStore.sourceError = error
        onErrorCodeChanged: settingsStore.recoveryNeeded = errorCode === "recovery"
    }
    SettingsStore {
        id: settingsStore
        onApplyRequested: request => { configurationFocus.active = false; settingsWriter.send(request); }
        onPreviewRequested: zone => {
            root.previewZone = zone;
            if (!previewReader.busy) previewReader.send({operation: "preview", timezone: zone});
        }
    }
    property string previewZone: ""
    SettingsBackend {
        id: catalogReader
        profile: root.profile
        Component.onCompleted: send({operation: "catalog"})
        onFinished: response => {
            if (response.ok) { settingsStore.catalog = response.catalog; settingsStore.catalogError = ""; }
            else settingsStore.catalogError = response.message || "Unable to load the installed settings catalog.";
        }
    }
    SettingsBackend {
        id: previewReader
        profile: root.profile
        onFinished: response => {
            if (request.timezone !== root.previewZone) { Qt.callLater(() => send({operation: "preview", timezone: root.previewZone})); return; }
            if (response.ok) { settingsStore.clockPreview = response.clock; settingsStore.previewError = ""; }
            else settingsStore.previewError = response.message || "Unable to preview this timezone.";
        }
    }
    SettingsBackend {
        id: settingsWriter
        profile: root.profile
        onFinished: response => { settingsStore.finish(response, request.operation); settingsSource.refresh(); focusTimer.restart(); }
    }
    FileView {
        path: root.profile + "/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.userState = JSON.parse(text()); root.wallpaperRevision++; } catch (e) { console.warn(e); } }
    }
    FileView {
        path: root.profile + "/theme/palette.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.palette = JSON.parse(text()); if (!clockProcess.running) clockProcess.running = true; }
            catch (e) { console.warn(e); }
        }
    }
    Process {
        id: clockProcess
        command: [root.profile + "/bin/lock-visuals", "clock"]
        stdout: StdioCollector { onStreamFinished: root.clockRevision++ }
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: if (!clockProcess.running) clockProcess.running = true }
    ClockSource { id: desktopTime; path: root.profile + "/theme/clock.json" }
    Process {
        id: statusProcess
        command: [root.profile + "/bin/desktop-action", "status"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.status = JSON.parse(text); } catch (e) { console.warn(e); } }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: statusProcess.running = true }
    SystemClock { id: clock; precision: SystemClock.Minutes; onDateChanged: Qt.callLater(root.refreshClock) }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") settingsStore.runtime = Object.assign({}, settingsStore.runtime, {activeLayout: event.data.slice(event.data.indexOf(",") + 1)});
        }
    }
    IpcHandler {
        target: "desktop"
        function toggle(name: string): void { root.toggle(name); }
        function control(name: string): void { root.control(name); }
        function key(key: string): void { root.typeKey(key); }
        function awake(active: bool): void { root.inhibitIdle = active; }
        function shutdown(): void { root.shutdown(); }
        function status(): string {
            return JSON.stringify({page: root.page, windows: ToplevelManager.toplevels.values.length,
                configurationOpen: root.configurationOpen, configurationScreen: root.configurationScreenName,
                configurationDirty: settingsStore.dirty, configurationBusy: settingsStore.busy,
                configurationCanApply: settingsStore.canApply, configurationConflict: settingsStore.conflict,
                configurationFieldErrors: settingsStore.fieldErrors, configurationRecoveryNeeded: settingsStore.recoveryNeeded,
                configurationError: settingsStore.error || settingsStore.sourceError,
                configurationQuery: configurationWindow.query, configurationFocus: configurationWindow.activeFocus,
                configurationConfirmingClose: configurationWindow.confirmingClose,
                hyprlandWindows: Hyprland.toplevels.values.length, screens: Quickshell.screens.length,
                overviewFocus: windows.activeFocus, selectedWindow: windows.currentIndex,
                selectedSessionAction: sessionMenu.selectedAction,
                barVisible: root.barVisible, barBottom: root.barBottom,
                widgetsVisible: root.desktopClockVisible, keyboardVisible: root.keyboardVisible,
                toolsDetached: root.toolsDetached, idleInhibited: root.inhibitIdle});
        }
    }

    component Chip: Button {
        id: chip
        property bool selected: false
        property bool urgent: false
        property color hoverColor: root.raised
        property color selectedHoverColor: root.accent
        padding: 0
        implicitHeight: 30
        implicitWidth: Math.max(34, contentItem.implicitWidth + 22)
        hoverEnabled: true
        background: Rectangle {
            radius: height / 2
            color: chip.selected ? (chip.hovered ? chip.selectedHoverColor : root.accent) : (chip.hovered || chip.visualFocus ? chip.hoverColor : "transparent")
            border.width: chip.visualFocus || chip.urgent ? 2 : 0
            border.color: root.accent
        }
        contentItem: Text {
            text: chip.text; color: chip.selected ? root.onAccent : root.ink
            font.family: root.uiFont; font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    FloatingWindow {
        visible: root.toolsDetached
        onVisibleChanged: if (!visible) root.toolsDetached = false
        title: "Desktop utilities"
        implicitWidth: 420; implicitHeight: 520
        color: root.surface
        ToolsContent { desktop: root; anchors.fill: parent; anchors.margins: 20 }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: desktopBackground
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            IdleInhibitor { window: desktopBackground; enabled: root.inhibitIdle }
            color: root.surface
            Image { anchors.fill: parent; fillMode: Image.PreserveAspectCrop; source: "file://" + root.wallpaper + "?v=" + root.wallpaperRevision; cache: false }
            PlacedClock {
                id: desktopClock
                objectName: "desktop-clock-group"
                visible: root.desktopClockVisible
                position: root.preferences.clockPlacement?.desktop || null
                safeTop: root.barVisible && !root.barBottom ? 56 : 16
                safeBottom: root.barVisible && root.barBottom ? 56 : 16
                readonly property real dialSize: Math.max(1, Math.min(230, desktopBackground.width - 32, desktopBackground.height - safeTop - safeBottom - dateCaption.height - 10))
                width: dialSize
                height: dialSize + 10 + dateCaption.height
                defaultY: desktopBackground.height - 70 - dialSize
                Image {
                    width: desktopClock.dialSize; height: width
                    source: root.clockRevision > 0 ? "file://" + root.profile + "/theme/clock.png?v=" + root.clockRevision : ""
                    cache: false
                    asynchronous: true
                    retainWhileLoading: true
                }
                Text {
                    id: dateCaption
                    objectName: "desktop-clock-date"
                    y: desktopClock.dialSize + 10
                    width: parent.width
                    text: desktopTime.snapshot.date || ""
                    color: root.ink
                    font.family: root.uiFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: root.barVisible
            anchors { top: !root.barBottom; bottom: root.barBottom; left: true; right: true }
            implicitHeight: 40
            color: root.surface
            WlrLayershell.namespace: "archsetup-panel"
            Row {
                id: barCenter
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    width: workspaceRow.implicitWidth + 12; height: 32; radius: 16; color: root.raised
                    Row {
                        id: workspaceRow
                        readonly property int workspaceCount: panel.width > 1100 ? 10 : 5
                        readonly property int firstWorkspace: root.workspaceStart(Hyprland.monitorFor(panel.screen)?.activeWorkspace?.id, workspaceCount)
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: workspaceRow.workspaceCount
                            Chip {
                                required property int index
                                readonly property int workspaceId: workspaceRow.firstWorkspace + index
                                hoverColor: Qt.tint(root.raised, Qt.alpha(root.accent, 0.18))
                                selectedHoverColor: Qt.tint(root.accent, Qt.alpha(root.onAccent, 0.16))
                                implicitWidth: Math.max(26, contentItem.implicitWidth + 10); implicitHeight: 26
                                text: String(workspaceId)
                                selected: Hyprland.monitorFor(panel.screen)?.activeWorkspace?.id === workspaceId
                                onClicked: root.workspace(workspaceId)
                            }
                        }
                    }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.toggle("overview") }
                }
                Rectangle {
                    width: timeRow.implicitWidth + 12; height: 32; radius: 16; color: root.raised
                    RowLayout {
                        id: timeRow
                        anchors.centerIn: parent
                        spacing: 4
                        Chip {
                            hoverColor: Qt.tint(root.raised, Qt.alpha(root.accent, 0.18))
                            selectedHoverColor: Qt.tint(root.accent, Qt.alpha(root.onAccent, 0.16))
                            text: (desktopTime.snapshot.time || Qt.formatDateTime(clock.date, "HH:mm")) + (panel.width > 1100 ? " · " + (desktopTime.snapshot.shortDate || Qt.formatDateTime(clock.date, "d MMM")) : "")
                            selected: root.timeCenterOpen && root.timeCenterScreen === panel.screen.name
                            Accessible.name: "Calendar and time tools"
                            onClicked: {
                                root.timeCenterScreen = panel.screen.name;
                                root.timeCenterOpen = !root.timeCenterOpen;
                                if (root.timeCenterOpen) timeCenter.forceActiveFocus();
                            }
                        }
                    }
                }
            }
            Chip {
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                visible: UPower.displayDevice.isLaptopBattery
                text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                Accessible.name: "Battery " + text
                onClicked: root.toggle("settings")
            }
            RowLayout {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 12 }
                spacing: 4
                Repeater {
                    model: panel.screen === Quickshell.screens[0] ? SystemTray.items : null
                    delegate: Chip {
                        id: trayButton
                        required property var modelData
                        implicitWidth: 30
                        Image { anchors.centerIn: parent; width: 18; height: 18; source: trayButton.modelData.icon }
                        Accessible.name: modelData.title
                        onClicked: modelData.onlyMenu ? modelData.display(panel, x, y) : modelData.activate()
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: trayButton.modelData.display(panel, trayButton.x, trayButton.y) }
                    }
                }
                Chip { text: root.status.volume; visible: panel.width > 1000; onClicked: root.toggle("settings") }
                Chip { text: "●"; Accessible.name: "Notifications"; onClicked: root.action("notifications") }
                Chip { text: "Power"; Accessible.name: "Session"; onClicked: root.toggle("session") }
            }
        }
    }

    FileView {
        id: taskFile
        path: root.profile + "/tasks.json"
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (!Array.isArray(saved) || !saved.every(task => typeof task.text === "string" && typeof task.day === "string" && typeof task.done === "boolean")) throw new Error("Invalid task data");
                timeCenter.tasks = saved;
                root.tasksLoaded = true;
            } catch (error) { root.taskError = "Could not load saved tasks. Original file preserved."; }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) root.tasksLoaded = true;
            else root.taskError = "Could not read saved tasks.";
        }
        onSaveFailed: root.taskError = "Could not save tasks."
    }
    WorldClockSource {
        id: worldClockSource
        active: timePanel.visible && timeCenter.currentPage === 2
    }
    FileView {
        id: zoneFile
        path: root.profile + "/world-clocks.json"
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (!Array.isArray(saved) || !saved.every(zone => typeof zone === "string")) throw new Error("Invalid timezone data");
                timeCenter.zones = saved;
                root.zonesLoaded = true;
            } catch (error) { root.zoneError = "Could not load saved clocks. Original file preserved."; }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) root.zonesLoaded = true;
            else root.zoneError = "Could not read saved clocks.";
        }
        onSaveFailed: root.zoneError = "Could not save clocks."
    }
    PanelWindow {
        id: timePanel
        visible: root.timeCenterOpen && root.barVisible
        onVisibleChanged: if (visible) Qt.callLater(() => timeCenter.forceActiveFocus())
        screen: Quickshell.screens.find(s => s.name === root.timeCenterScreen) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "archsetup-time-center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"
        TimePopupSurface {
            anchors.fill: parent
            bottomBar: root.barBottom
            onDismissed: timeCenter.closed()
            TimeCenter {
                id: timeCenter
                anchors.fill: parent
                surface: root.surface; raised: root.raised; textColor: root.ink
                accent: root.accent; accentText: root.onAccent; uiFont: root.uiFont
                timezoneTimes: worldClockSource.times
                timezoneError: worldClockSource.error
                zonesEditable: root.zonesLoaded
                onZonesEdited: if (root.zonesLoaded) zoneFile.setText(JSON.stringify(zones))
                tasksEditable: root.tasksLoaded
                onClosed: root.timeCenterOpen = false
                onTasksEdited: if (root.tasksLoaded) taskFile.setText(JSON.stringify(tasks))
                onTimerCompleted: Quickshell.execDetached(["notify-send", "Timer", "Time is up!"])
            }
            Text {
                visible: root.taskError !== "" || root.zoneError !== ""
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 6 }
                text: root.taskError || root.zoneError; color: root.accent; font.pixelSize: 11
            }
        }
    }

    // Dismiss on other monitors too, without moving the card or keyboard focus.
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: timePanel.visible && screen !== timePanel.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "archsetup-time-dismiss"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: timeCenter.closed() }
        }
    }

    PanelWindow {
        id: configurationPanel
        visible: root.configurationOpen
        screen: Quickshell.screens.find(s => s.name === root.configurationScreenName) || Quickshell.screens[0]
        onScreenChanged: if (screen && root.configurationOpen) root.configurationScreenName = screen.name
        implicitWidth: Math.min(1360, (screen?.width || 1360) - ((screen?.width || 1360) < 600 ? 16 : 48))
        implicitHeight: Math.min(840, (screen?.height || 840) - ((screen?.height || 840) < 400 ? 16 : 80))
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "archsetup-configuration"
        WlrLayershell.layer: settingsStore.busy ? WlrLayer.Bottom : WlrLayer.Top
        WlrLayershell.keyboardFocus: root.page === "" && !settingsStore.busy ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"
        ConfigurationWindow {
            id: configurationWindow
            anchors.fill: parent
            inset: false
            store: settingsStore
            uiFont: root.uiFont
            surface: root.surface
            raised: root.raised
            textColor: root.ink
            accent: root.accent
            accentText: root.onAccent
            onClosed: root.configurationOpen = false
        }
    }
    HyprlandFocusGrab {
        id: configurationFocus
        windows: [configurationPanel]
        // Request focus on opening/re-entry, then release the grab so other
        // applications and authorization dialogs can receive focus normally.
        onActiveChanged: if (active) releaseConfigurationFocus.restart()
    }
    Timer { id: releaseConfigurationFocus; interval: 50; onTriggered: configurationFocus.active = false }

    PanelWindow {
        id: overlay
        visible: root.page !== ""
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: root.page === "session" ? Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 0.97) : "#99000000"
        MouseArea { anchors.fill: parent; onClicked: root.page = "" }
        ShortcutHelp {
            id: shortcutHelp
            anchors.fill: parent
            visible: root.page === "help"
            bindings: shortcutSource.bindings
            loadError: shortcutSource.loadError
            uiFont: root.uiFont
            surface: root.surface
            raised: root.raised
            textColor: root.ink
            accent: root.accent
            onCancelled: root.page = ""
        }
        SessionMenu {
            id: sessionMenu
            anchors.fill: parent
            visible: root.page === "session"
            uiFont: root.uiFont
            fontSize: root.preferences.controlFontSize || 12
            textColor: root.ink
            light: root.light
            tileColor: root.palette.primaryContainer || root.raised
            selectionColor: root.accent
            selectedTextColor: root.onAccent
            labelColor: root.raised
            labelTextColor: root.ink
            reducedMotion: root.preferences.reducedMotion === true
            canFirmwareSetup: root.status.canFirmwareSetup === true
            onCancelled: root.page = ""
            onActivated: action => {
                root.page = "";
                if (action === "settings") root.openConfiguration();
                else root.action(action === "poweroff" ? "poweroff-confirmed" : action);
            }
        }
        Rectangle {
            visible: root.page !== "session" && root.page !== "help"
            width: Math.min(parent.width - 48, root.page === "overview" ? 1000 : 540)
            height: Math.min(parent.height - 80, root.page === "overview" ? 700 : 560)
            anchors.centerIn: parent; radius: 24; color: root.surface
            // Consume clicks inside the surface so only the backdrop dismisses it.
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 24; spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: root.page === "overview" ? "Your windows" : root.page === "settings" ? "Quick settings" : root.page === "tools" ? "Utilities" : root.page === "media" ? "Media" : "Session"; color: root.ink; font.family: root.uiFont; font.pixelSize: 24; Layout.fillWidth: true }
                    Chip { text: "Close"; onClicked: root.page = "" }
                }
                Item {
                    id: panelContent
                    Layout.fillWidth: true; Layout.fillHeight: true
                    focus: overlay.visible
                    Keys.onEscapePressed: root.page = ""
                    StackLayout {
                        anchors.fill: parent
                        currentIndex: root.page === "overview" ? 0 : root.page === "settings" ? 1 : root.page === "tools" ? 2 : 3
                        ColumnLayout {
                            RowLayout {
                                id: overviewWorkspaces
                                readonly property int firstWorkspace: root.workspaceStart(Hyprland.monitorFor(overlay.screen)?.activeWorkspace?.id, 10)
                                Repeater {
                                    model: 10
                                    Chip {
                                        required property int index
                                        readonly property int workspaceId: overviewWorkspaces.firstWorkspace + index
                                        text: String(workspaceId)
                                        selected: Hyprland.monitorFor(overlay.screen)?.activeWorkspace?.id === workspaceId
                                        onClicked: { root.workspace(workspaceId); root.page = ""; }
                                    }
                                }
                            }
                            GridView {
                                id: windows
                                Layout.fillWidth: true; Layout.fillHeight: true
                                clip: true; cellWidth: width > 700 ? width / 3 : width / 2; cellHeight: 200
                                model: ToplevelManager.toplevels
                                focus: root.page === "overview"
                                keyNavigationEnabled: true
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        const selected = ToplevelManager.toplevels.values[Math.max(0, currentIndex)];
                                        if (selected) { selected.activate(); root.page = ""; }
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        root.page = "";
                                        event.accepted = true;
                                    }
                                }
                                delegate: Rectangle {
                                    id: windowCard
                                    required property var modelData
                                    required property int index
                                    width: windows.cellWidth - 10; height: 190; radius: 16; color: root.raised
                                    border.width: windows.currentIndex === index ? 2 : 0; border.color: root.accent
                                    ScreencopyView { anchors { top: parent.top; left: parent.left; right: parent.right; bottom: title.top; margins: 8 } captureSource: windowCard.modelData; live: overlay.visible }
                                    Text { id: title; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 } text: windowCard.modelData.title; font.family: root.uiFont; color: root.ink; elide: Text.ElideRight }
                                    MouseArea { anchors.fill: parent; onClicked: { windowCard.modelData.activate(); root.page = ""; } }
                                }
                            }
                            Text { visible: windows.count === 0; text: "No open windows · Super+Enter opens a terminal"; color: root.ink }
                        }
                        ColumnLayout {
                            spacing: 12
                            Text { text: root.status.network + "  ·  Volume " + root.status.volume; color: root.ink; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Flow {
                                Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 8
                                Chip { text: "Volume −"; onClicked: Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]) }
                                Chip { text: "Volume +"; onClicked: Quickshell.execDetached(["wpctl", "set-volume", "-l", "1", "@DEFAULT_AUDIO_SINK@", "5%+"]) }
                                Chip { text: "Mute"; onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]) }
                                Chip { text: "Microphone"; onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]) }
                                Chip { text: "Audio devices"; onClicked: root.action("audio") }
                                Chip { text: "Network"; onClicked: root.action("network") }
                                Chip { text: "Bluetooth"; onClicked: root.action("bluetooth") }
                                Chip { text: "Brightness −"; visible: root.status.brightness; onClicked: Quickshell.execDetached(["brightnessctl", "-n2", "set", "5%-"]) }
                                Chip { text: "Brightness +"; visible: root.status.brightness; onClicked: Quickshell.execDetached(["brightnessctl", "set", "5%+"]) }
                                Chip { text: "Do not disturb"; onClicked: root.action("dnd") }
                                Chip { text: "Keep awake"; selected: root.inhibitIdle; onClicked: root.inhibitIdle = !root.inhibitIdle }
                                Chip { text: "Light / dark"; onClicked: root.action("theme") }
                                Chip { text: "Color theme · " + (root.palette.name || "Rose"); onClicked: { root.page = ""; root.action("theme-select"); } }
                                Chip { text: "Calculator"; onClicked: { root.page = ""; root.action("calculator"); } }
                                Chip { text: "Wallpaper"; onClicked: { root.page = ""; root.action("wallpaper"); } }
                                Chip { text: "Previous"; onClicked: Quickshell.execDetached(["playerctl", "previous"]) }
                                Chip { text: "Play / pause"; onClicked: Quickshell.execDetached(["playerctl", "play-pause"]) }
                                Chip { text: "Next"; onClicked: Quickshell.execDetached(["playerctl", "next"]) }
                                Chip { text: "Keyboard"; onClicked: { root.page = ""; root.control("keyboard"); } }
                            }
                            Item { Layout.fillHeight: true }
                            Text { text: desktopTime.snapshot.date || ""; color: root.ink }
                        }
                        ToolsContent { desktop: root }
                        ColumnLayout {
                            spacing: 16
                            Text { text: root.status.media || "Nothing playing"; textFormat: Text.PlainText; color: root.ink; font.family: root.uiFont; font.pixelSize: 20; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            RowLayout {
                                Chip { text: "Previous"; onClicked: Quickshell.execDetached(["playerctl", "previous"]) }
                                Chip { text: "Play / pause"; onClicked: Quickshell.execDetached(["playerctl", "play-pause"]) }
                                Chip { text: "Next"; onClicked: Quickshell.execDetached(["playerctl", "next"]) }
                            }
                            Chip { text: "Audio devices"; onClicked: root.action("audio") }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        visible: root.keyboardVisible
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0]
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 250
        color: root.surface
        WlrLayershell.namespace: "archsetup-keyboard"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 5
            RowLayout {
                Text { text: "Keyboard"; color: root.ink; font.family: root.uiFont; Layout.fillWidth: true }
                Chip { text: "Close"; onClicked: root.keyboardVisible = false }
            }
            Repeater {
                model: [
                    ["Escape", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "minus", "equal", "BackSpace"],
                    ["Tab", "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "bracketleft", "bracketright"],
                    ["a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon", "apostrophe", "Return"],
                    ["Shift", "z", "x", "c", "v", "b", "n", "m", "comma", "period", "slash", "Ctrl"],
                    ["Left", "Down", "space", "Up", "Right"]
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 4
                    Repeater {
                        model: parent.modelData
                        Chip {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.minimumWidth: 22
                            text: ({minus: "−", equal: "=", bracketleft: "[", bracketright: "]", semicolon: ";", apostrophe: "'", comma: ",", period: ".", slash: "/", space: "Space", Return: "Enter", BackSpace: "⌫"})[modelData] || (root.keyboardShift && modelData.length === 1 ? modelData.toUpperCase() : modelData)
                            selected: modelData === "Shift" && root.keyboardShift || modelData === "Ctrl" && root.keyboardControl
                            onClicked: root.typeKey(modelData)
                        }
                    }
                }
            }
        }
    }
}
