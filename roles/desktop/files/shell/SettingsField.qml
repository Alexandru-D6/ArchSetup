pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

TextField {
    id: field
    required property var theme
    implicitHeight: 40
    padding: 12
    color: theme.textColor
    placeholderTextColor: Qt.rgba(theme.textColor.r, theme.textColor.g, theme.textColor.b, 0.65)
    selectionColor: theme.accent
    selectedTextColor: theme.accentText
    font.family: theme.uiFont
    font.pixelSize: 13
    selectByMouse: true
    background: Rectangle {
        radius: 12
        color: field.theme.surface
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? field.theme.accent : field.theme.raised
    }
}
