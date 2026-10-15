pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row
    default property alias content: body.data
    required property var metadata
    required property var theme
    property bool highlighted: false
    property bool showLabel: true
    property string error: ""
    implicitHeight: stack.implicitHeight + 32
    radius: 18
    color: theme.raised
    border.width: highlighted ? 2 : 0
    border.color: theme.accent
    ColumnLayout {
        id: stack
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        Text {
            visible: row.showLabel
            text: row.metadata.label
            color: row.theme.textColor
            font.family: row.theme.uiFont
            font.pixelSize: 15
            font.weight: Font.Medium
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text {
            text: row.metadata.description
            color: row.theme.textColor
            opacity: 0.8
            font.family: row.theme.uiFont
            font.pixelSize: 13
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: 10
        }
        Text {
            visible: text.length > 0
            text: row.error
            color: row.theme.accent
            font.family: row.theme.uiFont
            font.pixelSize: 13
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
