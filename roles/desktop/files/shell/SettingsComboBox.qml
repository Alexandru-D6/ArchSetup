pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    required property var theme
    implicitHeight: 40
    textRole: "name"
    valueRole: "id"
    font.family: theme.uiFont
    font.pixelSize: 13
    palette.buttonText: theme.textColor
    palette.text: theme.textColor
    palette.windowText: theme.textColor
    palette.window: theme.surface
    palette.base: theme.surface
    palette.button: theme.raised
    palette.highlight: theme.accent
    palette.highlightedText: theme.accentText
    background: Rectangle {
        radius: 12
        color: control.theme.surface
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.theme.accent : control.theme.raised
    }
}
