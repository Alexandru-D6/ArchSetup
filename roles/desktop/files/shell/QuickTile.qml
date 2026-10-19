pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: tile
    required property var theme
    required property string symbol
    property string subtitle: ""
    property bool selected: false
    property bool available: true
    property bool hasDetails: false
    signal detailsRequested()
    implicitHeight: 66
    padding: 12
    rightPadding: hasDetails ? 34 : 12
    Accessible.name: text + ", " + subtitle
    background: Rectangle {
        radius: 18
        color: tile.selected ? tile.theme.accent : tile.theme.raised
        border.width: tile.visualFocus || tile.hovered ? 2 : 0
        border.color: tile.theme.accent
        opacity: tile.available ? 1 : 0.5
    }
    contentItem: RowLayout {
        spacing: 10
        opacity: tile.available ? 1 : 0.55
        SessionIcon { name: tile.symbol; color: tile.selected ? tile.theme.accentText : tile.theme.textColor; implicitWidth: 22; implicitHeight: 22 }
        ColumnLayout {
            spacing: 3
            Layout.fillWidth: true
            Text { text: tile.text; font.family: tile.theme.uiFont; font.pixelSize: 13; font.weight: Font.DemiBold; color: tile.selected ? tile.theme.accentText : tile.theme.textColor }
            Text { text: tile.subtitle; font.family: tile.theme.uiFont; font.pixelSize: 10; color: tile.selected ? tile.theme.accentText : tile.theme.textColor; opacity: 0.8; elide: Text.ElideRight; Layout.fillWidth: true }
        }
    }
    Button {
        id: details
        visible: tile.hasDetails
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
        width: 28; height: 40
        Accessible.name: tile.text + " options"
        onClicked: tile.detailsRequested()
        background: Rectangle { radius: 12; color: details.hovered || details.activeFocus ? Qt.alpha(tile.theme.textColor, 0.12) : "transparent" }
        contentItem: SessionIcon { name: "chevron"; color: tile.selected ? tile.theme.accentText : tile.theme.textColor; implicitWidth: 16; implicitHeight: 16 }
    }
}
