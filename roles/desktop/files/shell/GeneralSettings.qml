pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: page
    required property var store
    required property var registry
    required property var theme
    property string highlightedSetting: ""
    readonly property var powerSetting: registry.setting("general.lockPowerRequiresAuth")
    readonly property bool editable: store.loaded && !store.busy && !store.sourceError
    objectName: "settings-general-scroll"
    contentWidth: width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    function revealSetting(id) {
        const targets = {
            "general.timezone": [timezoneRow, timezonePicker],
            "general.utcOffset": [offsetRow, offsetValue],
            "general.clockPlacement.desktop": [desktopRow, desktopPosition],
            "general.clockPlacement.lockScreen": [lockRow, lockPosition],
            "general.keyboard.layouts": [keyboardRow, keyboardEditor],
            "general.lockPowerRequiresAuth": [powerRow, powerToggle]
        };
        const target = targets[id];
        if (!target) return false;
        contentY = Math.max(0, Math.min(target[0].y, contentHeight - height));
        highlightedSetting = id;
        highlightTimer.restart();
        if (target[1].focusPrimary) target[1].focusPrimary();
        else target[1].forceActiveFocus();
        return true;
    }
    Timer { id: highlightTimer; interval: 1800; onTriggered: page.highlightedSetting = "" }
    Timer { interval: 60000; running: page.visible && page.store.loaded; repeat: true; onTriggered: page.store.requestPreview() }

    ColumnLayout {
        id: form
        width: page.width - 12
        spacing: 20
        Text {
            text: "General"
            color: page.theme.textColor
            font.family: page.theme.uiFont
            font.pixelSize: 22
            Layout.fillWidth: true
        }
        Text {
            text: page.store.catalogError
            visible: text.length > 0
            color: page.theme.accent
            font.family: page.theme.uiFont
            font.pixelSize: 13
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        SettingsRow {
            id: timezoneRow
            objectName: "settings-row-general.timezone"
            Layout.fillWidth: true
            metadata: page.registry.setting("general.timezone")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            error: page.store.fieldErrors[metadata.id] || page.store.previewError
            SettingsPicker {
                id: timezonePicker
                objectName: "settings-timezone"
                Layout.fillWidth: true
                theme: page.theme
                items: page.store.catalog.timezones
                value: page.store.draft["general.timezone"] || ""
                placeholder: "Search timezones or cities…"
                choicePlaceholder: "Choose the system timezone"
                enabled: page.editable && items.length > 0
                onSelected: id => page.store.edit("general.timezone", id)
            }
        }
        SettingsRow {
            id: offsetRow
            objectName: "settings-row-general.utcOffset"
            Layout.fillWidth: true
            metadata: page.registry.setting("general.utcOffset")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            Text {
                id: offsetValue
                objectName: "settings-utc-offset"
                text: page.store.clockPreview.timezone === page.store.draft["general.timezone"] ? page.store.clockPreview.utcOffset + " · " + page.store.clockPreview.time + " · " + page.store.clockPreview.date : "Loading timezone preview…"
                color: page.theme.textColor
                font.family: page.theme.uiFont
                font.pixelSize: 14
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                activeFocusOnTab: true
            }
        }
        SettingsRow {
            id: desktopRow
            objectName: "settings-row-general.clockPlacement.desktop"
            Layout.fillWidth: true
            metadata: page.registry.setting("general.clockPlacement.desktop")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            error: page.store.fieldErrors[metadata.id] || ""
            ClockPositionEditor {
                id: desktopPosition
                objectName: "settings-desktop-position"
                Layout.fillWidth: true
                theme: page.theme
                position: page.store.draft["general.clockPlacement.desktop"] || null
                enabled: page.editable
                onEdited: position => page.store.edit("general.clockPlacement.desktop", position)
            }
        }
        SettingsRow {
            id: lockRow
            objectName: "settings-row-general.clockPlacement.lockScreen"
            Layout.fillWidth: true
            metadata: page.registry.setting("general.clockPlacement.lockScreen")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            error: page.store.fieldErrors[metadata.id] || ""
            ClockPositionEditor {
                id: lockPosition
                objectName: "settings-lock-position"
                Layout.fillWidth: true
                theme: page.theme
                lockScreen: true
                position: page.store.draft["general.clockPlacement.lockScreen"] || null
                enabled: page.editable
                onEdited: position => page.store.edit("general.clockPlacement.lockScreen", position)
            }
        }
        SettingsRow {
            id: keyboardRow
            objectName: "settings-row-general.keyboard.layouts"
            Layout.fillWidth: true
            metadata: page.registry.setting("general.keyboard.layouts")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            error: page.store.fieldErrors[metadata.id] || ""
            KeyboardLayoutEditor {
                id: keyboardEditor
                objectName: "settings-keyboard"
                Layout.fillWidth: true
                theme: page.theme
                layouts: page.store.draft["general.keyboard.layouts"] || []
                catalog: page.store.catalog.layouts
                maximumLayouts: page.store.catalog.maxLayouts
                activeLayout: page.store.runtime.activeLayout || ""
                enabled: page.editable && catalog.length > 0
                onEdited: layouts => page.store.edit("general.keyboard.layouts", layouts)
            }
        }
        Text {
            text: page.powerSetting.section
            color: page.theme.textColor
            font.family: page.theme.uiFont
            font.pixelSize: 15
            font.weight: Font.Medium
            Layout.fillWidth: true
        }
        Rectangle {
            id: powerRow
            objectName: "settings-row-general.lockPowerRequiresAuth"
            Layout.fillWidth: true
            implicitHeight: powerContent.implicitHeight + 32
            radius: 18
            color: page.theme.raised
            border.width: page.highlightedSetting === page.powerSetting.id ? 2 : 0
            border.color: page.theme.accent
            ColumnLayout {
                id: powerContent
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                CheckBox {
                    id: powerToggle
                    objectName: "settings-lock-power"
                    Layout.fillWidth: true
                    enabled: page.store.loaded && !page.store.busy && !page.store.sourceError
                    checked: page.store.draft[page.powerSetting.id] !== false
                    text: page.powerSetting.label
                    Accessible.description: page.powerSetting.description
                    onToggled: page.store.edit(page.powerSetting.id, checked)
                    padding: 2
                    spacing: 12
                    indicator: Rectangle {
                        implicitWidth: 24; implicitHeight: 24
                        x: powerToggle.leftPadding
                        y: Math.round((powerToggle.height - height) / 2)
                        radius: 7
                        color: powerToggle.checked ? page.theme.accent : page.theme.surface
                        border.width: powerToggle.activeFocus ? 3 : 1
                        border.color: powerToggle.activeFocus ? page.theme.textColor : page.theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            visible: powerToggle.checked
                            color: page.theme.accentText
                            font.pixelSize: 16
                        }
                    }
                    contentItem: Text {
                        leftPadding: powerToggle.indicator.width + powerToggle.spacing
                        text: powerToggle.text
                        wrapMode: Text.Wrap
                        color: page.theme.textColor
                        font.family: page.theme.uiFont
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        verticalAlignment: Text.AlignVCenter
                        opacity: powerToggle.enabled ? 1 : 0.5
                    }
                }
                Text {
                    text: page.powerSetting.description
                    color: page.theme.textColor
                    opacity: 0.8
                    font.family: page.theme.uiFont
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                Text {
                    text: "Applies the next time you lock the screen."
                    color: page.theme.textColor
                    opacity: 0.65
                    font.family: page.theme.uiFont
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                Text {
                    text: page.store.fieldErrors[page.powerSetting.id] || ""
                    visible: text.length > 0
                    color: page.theme.accent
                    font.family: page.theme.uiFont
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
        Item { Layout.preferredHeight: 8 }
    }
}
