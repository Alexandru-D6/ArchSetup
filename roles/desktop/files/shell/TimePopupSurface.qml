pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: surface
    default property alias content: card.data
    property alias cardItem: card
    property bool bottomBar: false
    signal dismissed()

    // This fills the transparent layer window. Outside presses are consumed so
    // dismissing the popup does not also activate the application underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: surface.dismissed()
    }
    Item {
        id: card
        width: Math.max(1, Math.min(580, surface.width - 16))
        height: Math.max(1, Math.min(600, surface.height - 64))
        anchors.horizontalCenter: parent.horizontalCenter
        y: surface.bottomBar ? surface.height - height - 46 : 46
        // Empty space inside the card is still part of the popup.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }
}
