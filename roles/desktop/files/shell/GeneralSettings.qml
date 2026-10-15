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
    objectName: "settings-general-scroll"
    contentWidth: width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    function revealSetting(id) {
        if (id !== powerSetting.id) return false;
        contentY = Math.max(0, Math.min(powerRow.y, contentHeight - height));
        highlightedSetting = id;
        highlightTimer.restart();
        powerToggle.forceActiveFocus();
        return true;
    }
    Timer { id: highlightTimer; interval: 1800; onTriggered: page.highlightedSetting = "" }

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
