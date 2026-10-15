pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: frame
    default property alias content: body.data
    property alias bodyItem: body
    property string title: ""
    property string closeObjectName: "window-close"
    property bool closeEnabled: true
    property bool inset: true
    property string uiFont: "DejaVu Sans"
    property color raised: "#ffe7eb"
    property color textColor: "#3d2c32"
    property color accent: "#bd0056"
    property color accentText: "#ffffff"
    readonly property int padding: width < 600 ? 16 : 24
    signal closeRequested()

    anchors.centerIn: parent
    width: inset ? Math.min(1360, parent.width - (parent.width < 600 ? 16 : 48)) : parent.width
    height: inset ? Math.min(840, parent.height - (parent.height < 400 ? 16 : 80)) : parent.height
    radius: 24
    color: "#fff8f9"
    border.width: 1
    border.color: raised
    // Each consumer owns its own dismissal policy, including backdrop clicks.
    MouseArea { anchors.fill: parent }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: frame.padding
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: frame.title
                color: frame.textColor
                font.family: frame.uiFont
                font.pixelSize: frame.width < 400 ? 20 : 24
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            SettingsButton {
                objectName: frame.closeObjectName
                text: "Close"
                theme: frame
                enabled: frame.closeEnabled
                Accessible.name: "Close " + frame.title.toLowerCase()
                onClicked: frame.closeRequested()
            }
        }
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
