pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: editor
    required property var theme
    property var position: null
    property bool lockScreen: false
    readonly property var defaultPoint: lockScreen ? {x: 0.5, y: 0.5} : {x: 0, y: 1}
    readonly property var point: position || defaultPoint
    signal edited(var position)
    spacing: 12
    function focusPrimary() { defaultButton.forceActiveFocus(); }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton {
            id: defaultButton
            objectName: editor.objectName + "-default"
            theme: editor.theme
            text: "Default"
            primary: editor.position === null
            onClicked: editor.edited(null)
        }
        SettingsButton {
            objectName: editor.objectName + "-randomize"
            theme: editor.theme
            text: "Randomize"
            onClicked: editor.edited({x: Math.random(), y: Math.random()})
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 420 ? 2 : 1
        columnSpacing: 16
        rowSpacing: 12
        GridLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            columns: 3
            rowSpacing: 5; columnSpacing: 5
            Repeater {
                model: ["Top left", "Top center", "Top right", "Center left", "Center", "Center right", "Bottom left", "Bottom center", "Bottom right"]
                SettingsButton {
                    required property int index
                    required property string modelData
                    objectName: editor.objectName + "-preset-" + index
                    theme: editor.theme
                    text: ["↖", "↑", "↗", "←", "•", "→", "↙", "↓", "↘"][index]
                    Accessible.name: modelData
                    primary: editor.position !== null && Math.abs(editor.point.x - (index % 3) / 2) < 0.001 && Math.abs(editor.point.y - Math.floor(index / 3) / 2) < 0.001
                    Layout.preferredWidth: 42
                    Layout.minimumWidth: 26
                    Layout.fillWidth: true
                    onClicked: editor.edited({x: (index % 3) / 2, y: Math.floor(index / 3) / 2})
                }
            }
        }
        Rectangle {
            objectName: editor.objectName + "-preview"
            Layout.fillWidth: true
            Layout.minimumWidth: 60
            Layout.maximumWidth: 300
            implicitHeight: Math.max(75, width * 0.48)
            radius: 10
            color: editor.theme.surface
            border.color: editor.theme.textColor
            border.width: 1
            Rectangle {
                visible: !editor.lockScreen
                x: 8; y: 6; width: parent.width - 16; height: 4; radius: 2
                color: editor.theme.raised
            }
            Rectangle {
                visible: editor.lockScreen
                width: parent.width * 0.3; height: 6; radius: 3
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                color: editor.theme.raised
            }
            Rectangle {
                id: previewClock
                width: Math.min(30, parent.width * 0.17)
                height: width
                radius: width / 2
                color: editor.theme.accent
                x: 10 + editor.point.x * Math.max(0, parent.width - 20 - width)
                y: 14 + editor.point.y * Math.max(0, parent.height - (editor.lockScreen ? 30 : 20) - height - 5)
                Rectangle { width: parent.width * 0.5; height: 2; radius: 1; color: editor.theme.accentText; anchors.centerIn: parent; rotation: -45 }
                Rectangle { width: parent.width * 0.3; height: 2; radius: 1; color: editor.theme.accentText; anchors.centerIn: parent; rotation: 45 }
                Rectangle { x: -3; y: parent.height + 3; width: parent.width + 6; height: 3; radius: 1; color: editor.theme.textColor }
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 12
        Repeater {
            model: ["Horizontal", "Vertical"]
            Column {
                id: coordinate
                required property int index
                required property string modelData
                spacing: 4
                Text {
                    text: coordinate.modelData + " %"
                    color: editor.theme.textColor
                    font.family: editor.theme.uiFont
                    font.pixelSize: 13
                }
                SpinBox {
                    objectName: editor.objectName + (coordinate.index === 0 ? "-x" : "-y")
                    from: 0; to: 100; stepSize: 5
                    width: Math.max(80, Math.min(140, editor.width))
                    value: Math.round((coordinate.index === 0 ? editor.point.x : editor.point.y) * 100)
                    editable: true
                    font.family: editor.theme.uiFont
                    palette.text: editor.theme.textColor
                    palette.base: editor.theme.surface
                    palette.button: editor.theme.surface
                    palette.buttonText: editor.theme.textColor
                    palette.highlight: editor.theme.accent
                    Accessible.name: coordinate.modelData + " percentage"
                    onValueModified: editor.edited(coordinate.index === 0 ? {x: value / 100, y: editor.point.y} : {x: editor.point.x, y: value / 100})
                }
            }
        }
    }
    Text {
        text: "Randomize chooses a position now. Apply keeps the chosen position."
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: editor.theme.textColor
        opacity: 0.7
        font.family: editor.theme.uiFont
        font.pixelSize: 12
    }
}
