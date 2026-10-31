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
    readonly property bool editable: store.loaded && !store.busy && !store.sourceError
    objectName: "settings-notifications-scroll"
    contentWidth: width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    function revealSetting(id) {
        let row = positionRow;
        let control = position;
        if (id !== "notifications.position") {
            const index = thresholds.model.findIndex(item => item.id === id);
            if (index < 0) return false;
            row = thresholds.itemAt(index);
            control = row.control;
        }
        highlightedSetting = id;
        contentY = Math.max(0, Math.min(row.y, contentHeight - height));
        control.forceActiveFocus();
        highlightTimer.restart();
        return true;
    }
    Timer { id: highlightTimer; interval: 1800; onTriggered: page.highlightedSetting = "" }
    ColumnLayout {
        id: form
        width: page.width - 12
        spacing: 20
        Text { text: "Notifications"; color: page.theme.textColor; font.family: page.theme.uiFont; font.pixelSize: 22; Layout.fillWidth: true }
        SettingsRow {
            id: positionRow
            Layout.fillWidth: true
            metadata: page.registry.setting("notifications.position")
            theme: page.theme
            highlighted: page.highlightedSetting === metadata.id
            error: page.store.fieldErrors[metadata.id] || ""
            SettingsComboBox {
                id: position
                objectName: "settings-notification-position"
                Layout.fillWidth: true
                theme: page.theme
                enabled: page.editable
                Accessible.name: positionRow.metadata.label
                model: [
                    {id: "top-left", name: "Top left"}, {id: "top-center", name: "Top center"}, {id: "top-right", name: "Top right"},
                    {id: "bottom-left", name: "Bottom left"}, {id: "bottom-center", name: "Bottom center"}, {id: "bottom-right", name: "Bottom right"}
                ]
                currentIndex: model.findIndex(item => item.id === page.store.draft["notifications.position"])
                onActivated: page.store.edit("notifications.position", currentValue)
            }
        }
        Text { text: "Battery"; color: page.theme.textColor; font.family: page.theme.uiFont; font.pixelSize: 18; Layout.fillWidth: true }
        Text {
            text: "Keep the suspend percentage below critical, and critical below low. Warnings apply only while running on battery."
            color: page.theme.textColor; font.family: page.theme.uiFont; font.pixelSize: 13
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        Repeater {
            id: thresholds
            model: [
                {id: "notifications.lowBatteryPercentage", fallback: 20},
                {id: "notifications.criticalBatteryPercentage", fallback: 10},
                {id: "notifications.suspendPercentage", fallback: 3}
            ]
            delegate: SettingsRow {
                id: thresholdRow
                required property var modelData
                property alias control: percentageControl
                Layout.fillWidth: true
                metadata: page.registry.setting(modelData.id)
                theme: page.theme
                highlighted: page.highlightedSetting === metadata.id
                error: page.store.fieldErrors[metadata.id] || ""
                SpinBox {
                    id: percentageControl
                    objectName: "settings-" + thresholdRow.modelData.id
                    from: 1; to: 100; editable: true
                    value: page.store.draft[thresholdRow.modelData.id] ?? thresholdRow.modelData.fallback
                    enabled: page.editable
                    Accessible.name: thresholdRow.metadata.label
                    onValueModified: page.store.edit(thresholdRow.modelData.id, value)
                    font.family: page.theme.uiFont
                    palette.button: page.theme.raised; palette.base: page.theme.surface
                    palette.text: page.theme.textColor; palette.buttonText: page.theme.textColor
                    palette.highlight: page.theme.accent; palette.highlightedText: page.theme.accentText
                }
            }
        }
        Item { Layout.preferredHeight: 8 }
    }
}
