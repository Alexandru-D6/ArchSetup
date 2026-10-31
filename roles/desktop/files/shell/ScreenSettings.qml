pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: page
    required property var store
    required property var registry
    required property var theme
    property string selectedOutput: ""
    property string highlightedSetting: ""
    readonly property var monitors: store.draft["screen.monitors"] || []
    readonly property var monitor: monitors.find(item => item.name === selectedOutput) || monitors[0] || null
    readonly property var display: (store.runtime.screens || []).find(item => monitor && item.name === monitor.name) || null
    readonly property bool editable: store.loaded && !store.busy && !store.sourceError && !store.runtime.screenError && display !== null
    readonly property string resolution: monitor ? monitor.mode.split("@")[0] : ""
    readonly property var modes: display ? display.modes : []
    readonly property var resolutions: Array.from(new Set(modes.map(mode => mode.split("@")[0]))).map(id => ({id: id, name: id.replace("x", " × ")}))
    readonly property var rates: modes.filter(mode => mode.split("@")[0] === resolution).map(mode => ({id: mode, name: mode.split("@")[1] + " Hz"}))
    readonly property var scales: {
        if (!monitor) return [];
        const sizes = resolution.split("x").map(Number);
        return Array.from(new Set([1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, monitor.scale])).sort((a, b) => a - b)
            .filter(scale => sizes.every(size => Math.abs(size / scale - Math.round(size / scale)) < 0.01))
            .map(id => ({id: id, name: Math.round(id * 100) + "%"}));
    }
    objectName: "settings-screen-scroll"
    contentWidth: width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    function edit(changes) {
        if (!monitor || !editable) return;
        const next = Object.assign({}, monitor, changes);
        if (changes.mode) {
            const sizes = next.mode.split("@")[0].split("x").map(Number);
            if (sizes.some(size => Math.abs(size / next.scale - Math.round(size / next.scale)) > 0.01)) next.scale = 1;
        }
        store.edit("screen.monitors", monitors.map(item => item.name === monitor.name ? next : item));
    }
    function revealSetting(id) {
        const targets = {"screen.monitors": [displayRow, displayPicker], "screen.resolution": [resolutionRow, resolutionPicker],
            "screen.refreshRate": [rateRow, ratePicker], "screen.scale": [scaleRow, scalePicker],
            "screen.rotation": [rotationRow, rotationPicker], "screen.position": [positionRow, xField]};
        const target = targets[id];
        if (!target) return false;
        contentY = Math.max(0, Math.min(target[0].y, contentHeight - height));
        highlightedSetting = id;
        highlightTimer.restart();
        target[1].forceActiveFocus();
        return true;
    }
    function place(direction) {
        const other = monitors.find(item => item.name !== monitor.name);
        if (!other) return;
        const size = other.mode.split("@")[0].split("x").map(Number);
        if (other.transform % 2) size.reverse();
        edit({x: other.x + (direction === "right" ? Math.round(size[0] / other.scale) : 0),
              y: other.y + (direction === "below" ? Math.round(size[1] / other.scale) : 0)});
    }
    Timer { id: highlightTimer; interval: 1800; onTriggered: page.highlightedSetting = "" }

    ColumnLayout {
        id: form
        width: page.width - 12
        spacing: 20
        Text {
            text: "Screen"
            color: page.theme.textColor
            font.family: page.theme.uiFont
            font.pixelSize: 22
            Layout.fillWidth: true
        }
        Text {
            text: page.store.runtime.screenError || (!page.monitors.length ? "No configurable displays connected." : "Apply to try your changes. Keep the new configuration within 20 seconds or the previous settings will be restored.")
            color: page.theme.textColor
            font.family: page.theme.uiFont
            font.pixelSize: 13
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text {
            text: page.store.fieldErrors["screen.monitors"] || ""
            visible: text.length > 0
            color: page.theme.accent
            font.family: page.theme.uiFont
            font.pixelSize: 13
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        SettingsRow {
            id: displayRow
            Layout.fillWidth: true
            metadata: page.registry.setting("screen.monitors")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            SettingsComboBox {
                id: displayPicker
                objectName: "settings-screen-output"
                theme: page.theme
                Layout.fillWidth: true
                model: page.monitors.map(item => ({id: item.name, name: item.name}))
                currentIndex: page.monitor ? page.monitors.findIndex(item => item.name === page.monitor.name) : -1
                enabled: !page.store.busy && page.monitors.length > 0
                Accessible.name: "Connected display"
                onActivated: page.selectedOutput = currentValue
            }
            Text {
                text: page.display ? page.display.description : ""
                color: page.theme.textColor
                font.family: page.theme.uiFont
                font.pixelSize: 12
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            MonitorLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                monitors: page.monitors
                selectedOutput: page.monitor ? page.monitor.name : ""
                theme: page.theme
                onSelected: name => page.selectedOutput = name
            }
        }
        SettingsRow {
            id: resolutionRow
            Layout.fillWidth: true
            metadata: page.registry.setting("screen.resolution")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            SettingsComboBox {
                id: resolutionPicker
                objectName: "settings-screen-resolution"
                theme: page.theme
                Layout.fillWidth: true
                model: page.resolutions
                currentIndex: page.resolutions.findIndex(item => item.id === page.resolution)
                enabled: page.editable
                Accessible.name: "Resolution"
                onActivated: {
                    const options = page.modes.filter(mode => mode.split("@")[0] === currentValue);
                    const oldRate = page.monitor.mode.split("@")[1];
                    page.edit({mode: options.find(mode => mode.split("@")[1] === oldRate) || options[0]});
                }
            }
        }
        SettingsRow {
            id: rateRow
            Layout.fillWidth: true
            metadata: page.registry.setting("screen.refreshRate")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            SettingsComboBox {
                id: ratePicker
                objectName: "settings-screen-refresh-rate"
                theme: page.theme
                Layout.fillWidth: true
                model: page.rates
                currentIndex: page.monitor ? page.rates.findIndex(item => item.id === page.monitor.mode) : -1
                enabled: page.editable
                Accessible.name: "Refresh rate"
                onActivated: page.edit({mode: currentValue})
            }
        }
        SettingsRow {
            id: scaleRow
            Layout.fillWidth: true
            metadata: page.registry.setting("screen.scale")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            SettingsComboBox {
                id: scalePicker
                objectName: "settings-screen-scale"
                theme: page.theme
                Layout.fillWidth: true
                model: page.scales
                currentIndex: page.monitor ? page.scales.findIndex(item => item.id === page.monitor.scale) : -1
                enabled: page.editable
                Accessible.name: "Scale"
                onActivated: page.edit({scale: currentValue})
            }
        }
        SettingsRow {
            id: rotationRow
            Layout.fillWidth: true
            metadata: page.registry.setting("screen.rotation")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            SettingsComboBox {
                id: rotationPicker
                objectName: "settings-screen-rotation"
                theme: page.theme
                Layout.fillWidth: true
                model: [{id: 0, name: "Landscape"}, {id: 1, name: "90° counterclockwise"},
                    {id: 2, name: "180°"}, {id: 3, name: "90° clockwise"},
                    {id: 4, name: "Flipped"}, {id: 5, name: "Flipped, 90° counterclockwise"},
                    {id: 6, name: "Flipped, 180°"}, {id: 7, name: "Flipped, 90° clockwise"}]
                currentIndex: page.monitor ? page.monitor.transform : -1
                enabled: page.editable
                Accessible.name: "Rotation"
                onActivated: page.edit({transform: currentValue})
            }
        }
        SettingsRow {
            id: positionRow
            Layout.fillWidth: true
            metadata: page.registry.setting("screen.position")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            GridLayout {
                columns: 2
                Layout.fillWidth: true
                Text { text: "Horizontal (X)"; color: page.theme.textColor; font.family: page.theme.uiFont; font.pixelSize: 13 }
                Text { text: "Vertical (Y)"; color: page.theme.textColor; font.family: page.theme.uiFont; font.pixelSize: 13 }
                SettingsField {
                    id: xField
                    objectName: "settings-screen-x"
                    theme: page.theme
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: page.monitor ? String(page.monitor.x) : ""
                    enabled: page.editable
                    Accessible.name: "Horizontal monitor position"
                    validator: IntValidator { bottom: -65535; top: 65535 }
                    onEditingFinished: if (acceptableInput) page.edit({x: Number(text)})
                }
                SettingsField {
                    objectName: "settings-screen-y"
                    theme: page.theme
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: page.monitor ? String(page.monitor.y) : ""
                    enabled: page.editable
                    Accessible.name: "Vertical monitor position"
                    validator: IntValidator { bottom: -65535; top: 65535 }
                    onEditingFinished: if (acceptableInput) page.edit({y: Number(text)})
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: page.monitors.length > 1
                SettingsButton { theme: page.theme; text: "Right of other display"; enabled: page.editable; onClicked: page.place("right") }
                SettingsButton { theme: page.theme; text: "Below other display"; enabled: page.editable; onClicked: page.place("below") }
            }
        }
    }
}
