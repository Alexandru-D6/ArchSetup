pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    required property var theme
    required property var notification
    property bool compact: false
    implicitHeight: contents.implicitHeight + 24
    radius: 18
    color: theme.raised
    ColumnLayout {
        id: contents
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Text { text: card.notification?.appName || "Notification"; textFormat: Text.PlainText; font.family: card.theme.uiFont; font.pixelSize: 11; color: card.theme.textColor; opacity: 0.65; elide: Text.ElideRight; Layout.fillWidth: true }
            SettingsButton { theme: card.theme; text: "×"; implicitWidth: 28; implicitHeight: 28; padding: 0; Accessible.name: "Dismiss notification"; onClicked: card.notification.dismiss() }
        }
        Text { text: card.notification?.summary || ""; textFormat: Text.PlainText; font.family: card.theme.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold; color: card.theme.textColor; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Text {
            text: card.notification?.body || ""; visible: text !== ""; textFormat: Text.PlainText
            font.family: card.theme.uiFont; font.pixelSize: 12; color: card.theme.textColor
            wrapMode: Text.Wrap; Layout.fillWidth: true
            maximumLineCount: card.compact ? 3 : 1000; elide: Text.ElideRight
        }
        Flow {
            Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 4
            Repeater {
                model: card.notification?.actions || []
                SettingsButton {
                    required property var modelData
                    theme: card.theme
                    text: modelData.text || (modelData.identifier === "default" ? "Open" : "Action")
                    onClicked: modelData.invoke()
                }
            }
        }
    }
}
