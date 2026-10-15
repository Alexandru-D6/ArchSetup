pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Button {
    id: button
    required property var theme
    property bool primary: false
    padding: 10
    implicitHeight: 36
    opacity: enabled ? 1 : 0.45
    background: Rectangle {
        radius: 14
        color: button.primary ? button.theme.accent : button.hovered || button.activeFocus ? button.theme.raised : "transparent"
        border.width: button.activeFocus ? 2 : 1
        border.color: button.activeFocus ? button.theme.accent : button.theme.raised
    }
    contentItem: Text {
        text: button.text
        color: button.primary ? button.theme.accentText : button.theme.textColor
        font.family: button.theme.uiFont
        font.pixelSize: 13
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
