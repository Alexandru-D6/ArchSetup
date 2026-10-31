pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    required property var theme
    required property var notification
    property bool compact: false
    // The freedesktop notification protocol defines critical urgency as 2.
    readonly property bool critical: notification?.urgency === 2
    implicitHeight: contents.implicitHeight + 24
    radius: 18
    color: critical ? theme.accent : theme.raised
    readonly property color foreground: critical ? theme.accentText : theme.textColor
    readonly property var controlsTheme: ({uiFont: theme.uiFont, textColor: foreground,
        raised: critical ? Qt.darker(theme.accent, 1.2) : theme.raised,
        accent: critical ? theme.accentText : theme.accent, accentText: critical ? theme.accent : theme.accentText})
    border.width: critical ? 2 : 1
    border.color: theme.accent
    ColumnLayout {
        id: contents
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Text { text: (card.critical ? "!  " : "") + (card.notification?.appName || "Notification"); textFormat: Text.PlainText; font.family: card.theme.uiFont; font.pixelSize: 11; color: card.foreground; opacity: 0.85; elide: Text.ElideRight; Layout.fillWidth: true }
            SettingsButton { objectName: "notification-dismiss"; theme: card.controlsTheme; text: "×"; implicitWidth: 28; implicitHeight: 28; padding: 0; Accessible.name: "Dismiss notification"; onClicked: card.notification.dismiss() }
        }
        Text { text: card.notification?.summary || ""; textFormat: Text.PlainText; font.family: card.theme.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold; color: card.foreground; wrapMode: Text.Wrap; maximumLineCount: card.compact ? 3 : 1000; elide: Text.ElideRight; Layout.fillWidth: true }
        Text {
            text: card.notification?.body || ""; visible: text !== ""; textFormat: Text.PlainText
            font.family: card.theme.uiFont; font.pixelSize: 12; color: card.foreground
            wrapMode: Text.Wrap; Layout.fillWidth: true
            maximumLineCount: card.compact ? 3 : 1000; elide: Text.ElideRight
        }
        Flow {
            Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 4
            Repeater {
                model: card.notification?.actions || []
                SettingsButton {
                    required property var modelData
                    theme: card.controlsTheme
                    text: modelData.text || (modelData.identifier === "default" ? "Open" : "Action")
                    onClicked: modelData.invoke()
                }
            }
        }
    }
}
